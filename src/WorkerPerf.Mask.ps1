#Requires -Version 5.1
# WorkerPerf report masking: collects the names of a whole capture and assigns their replacement names, then replaces
# them in texts and in the finished report data (definitions only).
# Requires WorkerPerf.Common.ps1, WorkerPerf.Load.ps1 (Open-WorkerPerfCsvReader), WorkerPerf.EventConfig.ps1 (default
# lists of accounts and domains that are not persons) and WorkerPerf.Events.ps1 (event and print driver readers, person check).
# Separate from the masking of the probe script Test-WorkerPerfSources.ps1, which is not used here.
# Get-WorkerPerfMaskRows and Get-WorkerPerfMaskList emit plain pipeline output: wrap calls in @(...).

# kinds of names that each level replaces
$script:WorkerPerfMaskLevelKinds = @{
    Personen = @('user', 'client', 'sid')
    Alles    = @('user', 'client', 'sid', 'server', 'share', 'domain', 'address', 'printer')
}
$script:WorkerPerfMaskIpv4Text = '(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)'
$script:WorkerPerfMaskIpv4 = New-Object System.Text.RegularExpressions.Regex ('^' + $script:WorkerPerfMaskIpv4Text + '$')
$script:WorkerPerfMaskSid = New-Object System.Text.RegularExpressions.Regex '^S-1-5-21-\d+-\d+-\d+-\d+$', 'IgnoreCase'
# folders under C:\Users that belong to no person
$script:WorkerPerfMaskProfileFolders = @('Public', 'Default', 'Default User', 'All Users')
# The server of a UNC path: letters, digits, '-', '_' and '.', neither starting nor ending with a full stop (so not the
# device prefixes \\?\ and \\.\, and not the full stop or bracket that follows it in a sentence).
$script:WorkerPerfMaskServerText = '(?<server>[\p{L}\p{N}_-](?:[\p{L}\p{N}_.-]*[\p{L}\p{N}_-])?)'
# Fixed patterns in path and instance texts, scanned left to right: an account SID; a UNC path with its server (a WebDAV
# suffix @SSL and @<port> is not part of it) and, when present, its share (\\server\share); a user folder <drive>:\Users\<name> (any drive, any case), and the user of a
# Citrix UPM mount path \Users\<user>_UPM_local (also without drive).
$script:WorkerPerfMaskPathPatternText = '(?<sid>(?<![\w-])S-1-5-21-\d+-\d+-\d+-\d+(?![\w-]))' +
    '|(?<unc>\\\\' + $script:WorkerPerfMaskServerText + '(?:@SSL)?(?:@\d{1,5})?\\(?<share>[^\\/\s,;"*:|<>]+)?)' +
    '|(?<drive>(?<![A-Za-z])[A-Za-z]:)?\\Users\\(?<folder>[^\\]+?)(?<upm>_UPM_local)?(?=\\|$)'
$script:WorkerPerfMaskPathPatterns = New-Object System.Text.RegularExpressions.Regex $script:WorkerPerfMaskPathPatternText, 'IgnoreCase'
# Free texts (meta.json) also hold addresses: an IPv4 address that is not part of a longer dotted number, not part of a
# path (no \ or / directly before or after) and not a version (not after "version", "v" and the like). Path segments,
# file names and version fields are never scanned for addresses.
$script:WorkerPerfMaskTextPatterns = New-Object System.Text.RegularExpressions.Regex ($script:WorkerPerfMaskPathPatternText +
    '|(?<ip>(?<![\d.\\/])(?<!\b(?:version|v)[\s:=]*)' + $script:WorkerPerfMaskIpv4Text + '(?!\.?\d)(?![\\/]))'), 'IgnoreCase'

# Running texts (report data): an account SID as a whole word, and the server of a UNC path (not the device prefixes \\?\
# and \\.\). An IPv4 shape is not looked for: in a text it cannot be told from a version number.
$script:WorkerPerfMaskSidWord = '(?<![\p{L}\p{N}-])S-1-5-21(?:-\d+){4}(?![\p{L}\p{N}]|-\d)'
$script:WorkerPerfMaskUncServer = '\\\\' + $script:WorkerPerfMaskServerText

# The replacing itself, in C# 5 (Windows PowerShell 5.1; only mscorlib, System and System.Management.Automation, which
# Add-Type references by default): one call per string and per match would cost a PowerShell function or script block
# call each, and the report data of a long capture holds several hundred thousand strings.
$script:WorkerPerfMaskSource = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using System.Text.RegularExpressions;

namespace WorkerPerf
{
    public sealed class ReportMasker
    {
        private readonly Regex pattern;
        private readonly int sidGroup;
        private readonly int serverGroup;
        private readonly Dictionary<string, string> lookup;
        private readonly Dictionary<string, bool> protectedNames;
        private readonly string other;
        private readonly Regex phrases;
        private readonly Dictionary<string, bool> addresses;
        // the report data repeats most of its strings (keys, kinds, users, applications): each is replaced once
        private readonly Dictionary<string, string> done = new Dictionary<string, string>(StringComparer.Ordinal);
        private const int DoneLimit = 200000;

        // pattern: alternatives of the names (no group), an unknown SID (group sid) and a UNC server (group server).
        // lookup: lower-case (invariant) name -> replacement; protectedNames: names that stay; other: the replacement
        // of a SID or UNC server that is not in lookup. phrasePattern: the protected names that hold white space or a
        // word delimiter, as one pattern with group p at every position (null or empty without such names).
        // addresses: the names of kind address.
        public ReportMasker(string pattern, IDictionary lookup, string[] protectedNames, string other, string phrasePattern, string[] addresses)
        {
            if (!string.IsNullOrEmpty(phrasePattern))
            {
                this.phrases = new Regex(phrasePattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
            }
            this.addresses = new Dictionary<string, bool>(StringComparer.Ordinal);
            foreach (string a in addresses) { if (!string.IsNullOrEmpty(a)) { this.addresses[a.ToLowerInvariant()] = true; } }
            this.pattern = new Regex(pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
            this.sidGroup = this.pattern.GroupNumberFromName("sid");
            this.serverGroup = this.pattern.GroupNumberFromName("server");
            this.lookup = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (DictionaryEntry e in lookup) { this.lookup[((string)e.Key).ToLowerInvariant()] = (string)e.Value; }
            this.protectedNames = new Dictionary<string, bool>(StringComparer.Ordinal);
            foreach (string p in protectedNames) { if (!string.IsNullOrEmpty(p)) { this.protectedNames[p.ToLowerInvariant()] = true; } }
            this.other = other ?? string.Empty;
        }

        public string Hide(string text)
        {
            if (string.IsNullOrEmpty(text)) { return text; }
            string rep;
            if (this.done.TryGetValue(text, out rep)) { return rep; }
            // the whole text is one name (a user, a client): no pattern needed. No protected name equals a name (the
            // caller drops those), so neither the word rule nor a phrase can keep a whole text that is a name.
            List<int> spans = null;
            if (!this.lookup.TryGetValue(text.ToLowerInvariant(), out rep))
            {
                rep = this.pattern.Replace(text, delegate(Match m) { return this.Evaluate(text, m, ref spans); });
            }
            if (this.done.Count < DoneLimit) { this.done[text] = rep; }
            return rep;
        }

        // spans: the occurrences of protected phrases in text (start, end pairs), found on the first name hit
        private string Evaluate(string text, Match m, ref List<int> spans)
        {
            string rep;
            if (this.serverGroup >= 0)
            {
                Group server = m.Groups[this.serverGroup];
                if (server.Success)
                {
                    if (!this.lookup.TryGetValue(server.Value.ToLowerInvariant(), out rep)) { rep = this.other; }
                    return m.Value.Substring(0, server.Index - m.Index) + rep;
                }
            }
            if (this.sidGroup >= 0 && m.Groups[this.sidGroup].Success)
            {
                if (this.lookup.TryGetValue(m.Value.ToLowerInvariant(), out rep)) { return rep; }
                return this.other;
            }
            if (this.IsProtected(text, m.Index, m.Length)) { return m.Value; }
            if (this.InPhrase(text, m.Index, m.Length, ref spans)) { return m.Value; }
            if (this.addresses.Count > 0 && this.addresses.ContainsKey(m.Value.ToLowerInvariant()) && InDottedNumber(text, m.Index, m.Length)) { return m.Value; }
            if (this.lookup.TryGetValue(m.Value.ToLowerInvariant(), out rep)) { return rep; }
            return m.Value;
        }

        // The hit lies completely inside an occurrence of a protected phrase ("Nexus KIS" keeps a user nexus).
        private bool InPhrase(string text, int index, int length, ref List<int> spans)
        {
            if (this.phrases == null) { return false; }
            if (spans == null)
            {
                spans = new List<int>();
                foreach (Match p in this.phrases.Matches(text))
                {
                    Group g = p.Groups["p"];
                    if (g.Success) { spans.Add(g.Index); spans.Add(g.Index + g.Length); }
                }
            }
            for (int i = 0; i < spans.Count; i += 2)
            {
                if (spans[i] <= index && index + length <= spans[i + 1]) { return true; }
            }
            return false;
        }

        // An address directly after a digit and a full stop or directly before a full stop and a digit is part of a
        // longer dotted number (a version), not the address.
        private static bool InDottedNumber(string text, int index, int length)
        {
            if (index >= 2 && text[index - 1] == '.' && char.IsDigit(text[index - 2])) { return true; }
            int end = index + length;
            return end + 1 < text.Length && text[end] == '.' && char.IsDigit(text[end + 1]);
        }

        private static bool IsDelimiter(char c)
        {
            if (char.IsWhiteSpace(c)) { return true; }
            switch (c)
            {
                case '\\': case '/': case '(': case ')': case '[': case ']': case ',': case ';': case ':':
                case '"': case '\'': case '<': case '>': case '|': case '=':
                    return true;
                default:
                    return false;
            }
        }

        // The word around a hit (bounded by white space and \ / ( ) [ ] , ; : " ' < > | =) equals a protected name,
        // also without the full stops at its end (a name at the end of a sentence).
        private bool IsProtected(string text, int index, int length)
        {
            if (this.protectedNames.Count == 0) { return false; }
            int a = index;
            while (a > 0 && !IsDelimiter(text[a - 1])) { a--; }
            int b = index + length;
            while (b < text.Length && !IsDelimiter(text[b])) { b++; }
            string word = text.Substring(a, b - a).ToLowerInvariant();
            if (this.protectedNames.ContainsKey(word)) { return true; }
            string trimmed = word.TrimEnd('.');
            return trimmed.Length > 0 && trimmed.Length < word.Length && this.protectedNames.ContainsKey(trimmed);
        }

        // A new structure: dictionaries and custom objects become ordered dictionaries, lists become arrays (string[]
        // stays string[], an array of a value type is copied), strings are masked; a StringBuilder (pre-rendered
        // series) and numbers, booleans, times, enums and guids stay as they are, any other object becomes its masked
        // text. Keys and property names stay, except in the dictionaries named in keyedMaps, whose keys come from the
        // recorded data: there they are masked, and a key that becomes equal to an earlier one gets " (2)", " (3)" ...
        // The string values of the fields named in keywordFields stay. Both lists name a field by its key ("kind") or
        // by the key of the record that holds it and its key ("procs.role"); list levels do not count.
        public object Protect(object value, string[] keyedMaps, string[] keywordFields)
        {
            Dictionary<string, bool> maps = ToSet(keyedMaps);
            Dictionary<string, bool> keywords = ToSet(keywordFields);
            return this.Node(value, string.Empty, string.Empty, maps, keywords);
        }

        public object Protect(object value)
        {
            return this.Protect(value, new string[0], new string[0]);
        }

        private static Dictionary<string, bool> ToSet(string[] names)
        {
            Dictionary<string, bool> set = new Dictionary<string, bool>(StringComparer.Ordinal);
            if (names != null) { foreach (string n in names) { if (!string.IsNullOrEmpty(n)) { set[n] = true; } } }
            return set;
        }

        private static bool Named(Dictionary<string, bool> set, string holder, string field)
        {
            if (set.Count == 0) { return false; }
            return set.ContainsKey(field) || set.ContainsKey(holder + "." + field);
        }

        // holder: the key of the record that holds this value; field: the key of this value (both '' at the top)
        private object Node(object value, string holder, string field, Dictionary<string, bool> maps, Dictionary<string, bool> keywords)
        {
            if (value == null) { return null; }
            string s = value as string;
            if (s != null) { return Named(keywords, holder, field) ? s : this.Hide(s); }
            PSObject ps = value as PSObject;
            if (ps != null)
            {
                object inner = ps.BaseObject;
                if (inner is PSCustomObject)
                {
                    bool maskObjectKeys = Named(maps, holder, field);
                    OrderedDictionary po = new OrderedDictionary(StringComparer.OrdinalIgnoreCase);
                    foreach (PSPropertyInfo p in ps.Properties) { this.AddKey(po, p.Name, this.Node(p.Value, field, p.Name, maps, keywords), maskObjectKeys); }
                    return po;
                }
                if (IsKept(inner)) { return value; }
                return this.Node(inner, holder, field, maps, keywords);
            }
            if (value is StringBuilder || IsKept(value)) { return value; }
            if (value is ValueType) { return this.Hide(Convert.ToString(value, CultureInfo.InvariantCulture)); }
            IDictionary dict = value as IDictionary;
            if (dict != null)
            {
                bool maskKeys = Named(maps, holder, field);
                OrderedDictionary od = new OrderedDictionary(StringComparer.OrdinalIgnoreCase);
                foreach (DictionaryEntry e in dict)
                {
                    string k = e.Key as string;
                    if (k == null) { k = Convert.ToString(e.Key, CultureInfo.InvariantCulture); }
                    this.AddKey(od, e.Key, this.Node(e.Value, field, k, maps, keywords), maskKeys);
                }
                return od;
            }
            Array arr = value as Array;
            if (arr != null && arr.Rank == 1)
            {
                Type et = arr.GetType().GetElementType();
                if (et.IsValueType) { return arr.Clone(); }
                if (et == typeof(string))
                {
                    string[] src = (string[])arr;
                    string[] dst = new string[src.Length];
                    bool keep = Named(keywords, holder, field);
                    for (int i = 0; i < src.Length; i++) { dst[i] = keep ? src[i] : this.Hide(src[i]); }
                    return dst;
                }
            }
            IEnumerable list = value as IEnumerable;
            if (list != null)
            {
                List<object> items = new List<object>();
                foreach (object x in list) { items.Add(this.Node(x, holder, field, maps, keywords)); }
                return items.ToArray();
            }
            // any other object (an uri, a file, a version ...): its text form, masked, so that nothing passes unmasked
            return this.Hide(Convert.ToString(value, CultureInfo.InvariantCulture));
        }

        // Values that stay as they are: numbers, booleans, characters, date and time values, time spans, enums and guids.
        private static bool IsKept(object value)
        {
            if (!(value is ValueType)) { return false; }
            Type t = value.GetType();
            return t.IsPrimitive || t.IsEnum || value is decimal || value is DateTime || value is DateTimeOffset || value is TimeSpan || value is Guid;
        }

        private void AddKey(OrderedDictionary od, object key, object value, bool mask)
        {
            string k = key as string;
            if (k == null) { od[key] = value; return; }
            if (mask) { k = this.Hide(k); }
            if (od.Contains(k))
            {
                int n = 2;
                while (od.Contains(k + " (" + n.ToString(System.Globalization.CultureInfo.InvariantCulture) + ")")) { n++; }
                k = k + " (" + n.ToString(System.Globalization.CultureInfo.InvariantCulture) + ")";
            }
            od.Add(k, value);
        }
    }
}
'@

function Get-WorkerPerfMaskRows {
    # The distinct value combinations of some columns of a capture file, in the order of their first row, each as
    # string[] (a column the file lacks gives ''). Columns by the file's own header; a missing file gives nothing.
    param([string]$Path, [string]$FileName, [string[]]$Columns)
    $seen = @{}
    $reader = $null
    try {
        $csv = Open-WorkerPerfCsvReader $Path $FileName -OwnHeader
        $reader = $csv.Reader; $need = $csv.Need
        $ix = @($Columns | ForEach-Object { if ($csv.Col.ContainsKey($_)) { [int]$csv.Col[$_] } else { -1 } })
        while ($null -ne $reader -and $null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            $vals = New-Object string[] $ix.Count
            for ($i = 0; $i -lt $ix.Count; $i++) { $vals[$i] = $(if ($ix[$i] -ge 0) { $f[$ix[$i]] } else { '' }) }
            $key = [string]::Join([string][char]0, $vals)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            , $vals
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
}

function Add-WorkerPerfMaskName($State, [string]$Kind, [string]$Name) {
    # Takes a name once (without regard to case), in the spelling and at the place of its first appearance; an empty
    # name is passed over. A name already taken keeps its kind, except that user, client and sid (replaced in both
    # levels) win over the kinds only level Alles replaces: a client that is also an endpoint host is a client.
    # Numbers are given at the end, in the order of the names, per kind.
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $n = $Name.Trim()
    $key = $n.ToLowerInvariant()
    $rec = $State.Seen[$key]
    if ($null -ne $rec) {
        $person = $script:WorkerPerfMaskLevelKinds['Personen']
        if ($person -contains $Kind -and $person -notcontains $rec.Kind) { $rec.Kind = $Kind }
        return
    }
    $rec = @{ Kind = $Kind; Name = $n }
    $State.Seen[$key] = $rec
    $State.Records.Add($rec)
}

function Add-WorkerPerfMaskProtected($State, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $n = $Name.Trim()
    $key = $n.ToLowerInvariant()
    if ($State.ProtectedSeen.ContainsKey($key)) { return }
    $State.ProtectedSeen[$key] = $true
    $State.Protected.Add($n)
}

function Add-WorkerPerfMaskHost($State, [string]$HostName) {
    # A host: an IPv4 address, else a server name (leading backslashes of an SMB server name dropped). The DNS suffix of
    # a server name with more than one label after the host (fs01.sim.local -> sim.local) is a domain.
    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    $h = $HostName.Trim().TrimStart('\')
    if ($script:WorkerPerfMaskIpv4.IsMatch($h)) { Add-WorkerPerfMaskName $State 'address' $h; return }
    Add-WorkerPerfMaskName $State 'server' $h
    $dot = $h.IndexOf('.')
    if ($dot -gt 0 -and $h.IndexOf('.', $dot + 1) -gt $dot + 1 -and -not $h.EndsWith('.')) { Add-WorkerPerfMaskName $State 'domain' $h.Substring($dot + 1) }
}

function Add-WorkerPerfMaskUncName($State, [string]$Kind, [string]$Name) {
    # A share or printer name, then the server of its UNC path (\\server\...) when it has one.
    Add-WorkerPerfMaskName $State $Kind $Name
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $m = [regex]::Match($Name.Trim(), '^\\\\([^\\]+)\\')
    if ($m.Success) { Add-WorkerPerfMaskHost $State $m.Groups[1].Value }
}

function Test-WorkerPerfMaskVirtualDomain($State, [string]$Domain) {
    # $true for the domain part of a virtual or built-in account (nonPersonDomains: NT SERVICE, Window Manager ...).
    if ([string]::IsNullOrEmpty($Domain)) { return $false }
    foreach ($p in @(Get-WorkerPerfField $State.EventConfig 'NonPersonDomains')) {
        if ($null -ne $p -and (Test-WorkerPerfAccountPattern $Domain $p)) { return $true }
    }
    return $false
}

function Add-WorkerPerfMaskAccount($State, [string]$Account, [string]$Domain, [bool]$CheckPerson) {
    # An account name "<domain>\<name>", "<name>@<domain>" or "<name>": an account SID gives a sid, else the name gives
    # the user and its domain part (else -Domain) the domain. -CheckPerson (accounts from events and paths): an account
    # whose domain part is virtual (nonPersonDomains) or whose name is not a person (nonPersonAccounts: SYSTEM, DWM-1 ...)
    # gives neither user nor domain, except a computer account NAME$, which gives the server NAME and the domain.
    if ([string]::IsNullOrWhiteSpace($Account)) { return }
    $a = $Account.Trim()
    $name = $a
    $dom = $Domain
    $cut = $a.LastIndexOf('\')
    $at = $a.LastIndexOf('@')
    if ($cut -ge 0) { $name = $a.Substring($cut + 1); if ($cut -gt 0) { $dom = $a.Substring(0, $cut) } }
    elseif ($at -gt 0 -and $at -lt $a.Length - 1) { $name = $a.Substring(0, $at); $dom = $a.Substring($at + 1) }
    if ($script:WorkerPerfMaskSid.IsMatch($name)) { Add-WorkerPerfMaskName $State 'sid' $name; return }
    if (-not $CheckPerson) { Add-WorkerPerfMaskName $State 'user' $name }
    elseif (Test-WorkerPerfMaskVirtualDomain $State $dom) { return }
    elseif (Test-WorkerPerfEventPersonUser $name $State.EventConfig) { Add-WorkerPerfMaskName $State 'user' $name }
    elseif ($name.Length -gt 1 -and $name.EndsWith('$')) { Add-WorkerPerfMaskHost $State $name.Substring(0, $name.Length - 1) }
    else { return }
    Add-WorkerPerfMaskName $State 'domain' $dom
}

function Add-WorkerPerfMaskPatternNames($State, [string]$Text, [System.Text.RegularExpressions.Regex]$Patterns) {
    # The names the fixed patterns find in a text, in their order in the text.
    if ([string]::IsNullOrEmpty($Text)) { return }
    foreach ($m in $Patterns.Matches($Text)) {
        if ($m.Groups['sid'].Success) { Add-WorkerPerfMaskName $State 'sid' $m.Groups['sid'].Value }
        elseif ($m.Groups['unc'].Success) {
            if ($m.Groups['share'].Success) { Add-WorkerPerfMaskName $State 'share' ($m.Groups['unc'].Value) }
            Add-WorkerPerfMaskHost $State $m.Groups['server'].Value
        }
        elseif ($m.Groups['upm'].Success) { Add-WorkerPerfMaskAccount $State $m.Groups['folder'].Value '' $true }
        elseif ($m.Groups['drive'].Success) {
            $folder = $m.Groups['folder'].Value
            $plain = @($script:WorkerPerfMaskProfileFolders | Where-Object { [string]::Equals($_, $folder, [StringComparison]::OrdinalIgnoreCase) })
            if ($plain.Count -eq 0) { Add-WorkerPerfMaskAccount $State $folder '' $true }
        }
        elseif ($m.Groups['ip'].Success) { Add-WorkerPerfMaskName $State 'address' $m.Groups['ip'].Value }
    }
}

function New-WorkerPerfMask {
    # The names of a whole capture (never a time cut, so every report of one capture uses the same replacements) and their
    # replacement names. Files are read in a fixed order, each from its first line on; the order of first appearance
    # decides the numbers. The numbers do not depend on the level: Personen keeps the numbers of Alles.
    # Returns @{ Level; Entries = @{ Kind; Name; Replacement }[] of the level, in order of first appearance;
    # Protected = string[] of names that must stay (process, service, application, module, driver, endpoint and role names);
    # Lookup = lower-case name -> replacement; Regex = one pattern of all names of the level, longer before shorter,
    # whole names only, without regard to case ($null without names) }.
    # -EventConfig: from Read-WorkerPerfEventConfig (NonPersonAccounts, NonPersonDomains); without it the built-in lists.
    param([string]$Path, [ValidateSet('Personen', 'Alles')][string]$Level, [hashtable]$Texts, [string[]]$RoleLabels = @(), $EventConfig = $null)
    if ($null -eq $EventConfig) {
        $EventConfig = @{ NonPersonAccounts = $script:WorkerPerfDefaultNonPersonAccounts; NonPersonDomains = $script:WorkerPerfDefaultNonPersonDomains }
    }
    $st = @{ Seen = @{}; Records = (New-Object System.Collections.Generic.List[object])
        Protected = (New-Object System.Collections.Generic.List[string]); ProtectedSeen = @{}; EventConfig = $EventConfig }

    # (1) meta.json: the worker and the endpoints' hosts
    $metaPath = Join-Path $Path 'meta.json'
    if (-not (Test-Path -LiteralPath $metaPath) -and (Test-Path -LiteralPath ($metaPath + '.tmp'))) { $metaPath = $metaPath + '.tmp' }
    $meta = $null
    if (Test-Path -LiteralPath $metaPath) { $meta = ConvertFrom-WorkerPerfJsonFile $metaPath }
    Add-WorkerPerfMaskHost $st ([string](Get-WorkerPerfField $meta 'Computer'))
    $endpoints = @(Get-WorkerPerfField $meta 'Endpoints' | Where-Object { $null -ne $_ })
    foreach ($e in $endpoints) { Add-WorkerPerfMaskHost $st ([string](Get-WorkerPerfField $e 'Host')) }

    # (2) sessions.csv (the session's user as it is, without the check for accounts that are not persons)
    $winStations = New-Object System.Collections.Generic.List[string]
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'sessions.csv' @('User', 'Domain', 'ClientName', 'WinStation'))) {
        Add-WorkerPerfMaskAccount $st $r[0] $r[1] $false
        Add-WorkerPerfMaskName $st 'client' $r[2]
        $winStations.Add($r[3])
    }
    # (2a) citrix.csv: an ICA instance "<WinStation> (<domain>\<user>)" or "<WinStation> (<user>)" names its user
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'citrix.csv' @('Instance'))) {
        $m = [regex]::Match($r[0], '^(.+?)\s*\(([^()]*)\)\s*$')
        if ($m.Success) { Add-WorkerPerfMaskAccount $st $m.Groups[2].Value '' $false }
    }
    # (3) shares.csv, (4) volumes.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'shares.csv' @('Share'))) { Add-WorkerPerfMaskUncName $st 'share' $r[0] }
    $volumes = @(Get-WorkerPerfMaskRows $Path 'volumes.csv' @('Volume', 'Backing'))
    foreach ($r in $volumes) { Add-WorkerPerfMaskUncName $st 'share' $r[1] }
    # (5) probes.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'probes.csv' @('Host'))) { Add-WorkerPerfMaskHost $st $r[0] }

    # (6) events.csv, then events_before.csv (each ordered by time, as the reader gives them)
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($file in 'events.csv', 'events_before.csv') {
        foreach ($ev in @(Read-WorkerPerfEventCsv $Path $file)) {
            $events.Add($ev)
            Add-WorkerPerfMaskAccount $st ([string]$ev['User']) '' $true
            Add-WorkerPerfMaskUncName $st 'printer' ([string]$ev['Printer'])
            if ($ev['Group'] -eq 'fileserver') { Add-WorkerPerfMaskHost $st ([string]$ev['Object']) }
        }
    }
    # (7) printqueues.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'printqueues.csv' @('Queue'))) { Add-WorkerPerfMaskUncName $st 'printer' $r[0] }

    # (8) fixed patterns: procinfo.csv Path, volumes.csv Volume and Backing, sessions.csv WinStation, the name fields of
    # the events (User, Printer, Object; not Text: it never reaches a masked report), then with addresses the free texts
    # of meta.json (source details and error messages)
    $procs = @(Get-WorkerPerfMaskRows $Path 'procinfo.csv' @('Name', 'Path', 'Services'))
    $pathTexts = New-Object System.Collections.Generic.List[string]
    foreach ($r in $procs) { $pathTexts.Add($r[1]) }
    foreach ($r in $volumes) { $pathTexts.Add($r[0]); $pathTexts.Add($r[1]) }
    $pathTexts.AddRange($winStations)
    foreach ($ev in $events) { foreach ($c in 'User', 'Printer', 'Object') { $pathTexts.Add([string]$ev[$c]) } }
    foreach ($t in $pathTexts) { Add-WorkerPerfMaskPatternNames $st $t $script:WorkerPerfMaskPathPatterns }
    $freeTexts = New-Object System.Collections.Generic.List[string]
    $sources = Get-WorkerPerfField $meta 'Sources'
    if ($null -ne $sources) { foreach ($p in $sources.PSObject.Properties) { $freeTexts.Add([string](Get-WorkerPerfField $p.Value 'Detail')) } }
    $errors = Get-WorkerPerfField $meta 'SourceErrors'
    if ($null -ne $errors) { foreach ($p in $errors.PSObject.Properties) { $freeTexts.Add([string](Get-WorkerPerfField $p.Value 'FirstMessage')) } }
    $freeTexts.Add([string](Get-WorkerPerfField $meta 'EndMessage'))
    foreach ($t in $freeTexts) { Add-WorkerPerfMaskPatternNames $st $t $script:WorkerPerfMaskTextPatterns }

    # names that stay
    foreach ($r in $procs) {
        Add-WorkerPerfMaskProtected $st $r[0]
        foreach ($s in $r[2].Split(';')) { Add-WorkerPerfMaskProtected $st $s }
    }
    foreach ($ev in $events) { foreach ($c in 'App', 'Module', 'Service', 'Driver') { Add-WorkerPerfMaskProtected $st ([string]$ev[$c]) } }
    foreach ($d in @(Read-WorkerPerfPrintDrivers $Path)) { Add-WorkerPerfMaskProtected $st $d.Name; Add-WorkerPerfMaskProtected $st $d.Manufacturer }
    foreach ($e in $endpoints) { Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Name')); Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Role')) }
    foreach ($l in $RoleLabels) { Add-WorkerPerfMaskProtected $st $l }

    # numbers per kind in the order of the names (whatever the level), then the level's kinds
    $numbers = @{}
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($rec in $st.Records) {
        $no = 1
        if ($numbers.ContainsKey($rec.Kind)) { $no = [int]$numbers[$rec.Kind] + 1 }
        $numbers[$rec.Kind] = $no
        $all.Add(@{ Kind = $rec.Kind; Name = $rec.Name; Replacement = ($Texts['mask.' + $rec.Kind] -f $no) })
    }
    $kinds = $script:WorkerPerfMaskLevelKinds[$Level]
    $entries = @($all | Where-Object { $kinds -contains $_.Kind })
    $mask = @{ Level = $Level; Other = [string]$Texts['mask.other'] }
    Set-WorkerPerfMaskNames -Mask $mask -Entries $entries -Protected ([string[]]$st.Protected.ToArray())
    return $mask
}

function Set-WorkerPerfMaskNames {
    # Sets the names of a mask (made by New-WorkerPerfMask, which calls this at its end): Entries = @{ Kind; Name;
    # Replacement }[]; Protected; Lookup = lower-case name -> replacement; Regex = one pattern of all names, longer
    # before shorter, whole names only, without regard to case ($null without names); Masker = the replacer that
    # Hide-WorkerPerfReportText and Protect-WorkerPerfReportData use. Uses Mask.Level and Mask.Other (the text of
    # mask.other). Changes the mask in place and returns nothing.
    param($Mask, [object[]]$Entries = @(), [string[]]$Protected = @())
    if (-not ('WorkerPerf.ReportMasker' -as [type])) { Add-Type -TypeDefinition $script:WorkerPerfMaskSource -Language CSharp }
    $entries = @($Entries | Where-Object { $null -ne $_ })
    $lookup = @{}
    foreach ($e in $entries) { $lookup[([string]$e.Name).ToLowerInvariant()] = [string]$e.Replacement }
    $regex = $null
    $alternatives = New-Object System.Collections.Generic.List[string]
    if ($entries.Count -gt 0) {
        # longer names first (then ordinal), so that a short name never cuts a longer one; whole names: no letter or
        # digit directly before or after
        $names = [string[]]@($entries | ForEach-Object { [string]$_.Name })
        [Array]::Sort($names, [Comparison[string]] { param($a, $b)
                if ($a.Length -ne $b.Length) { return $b.Length - $a.Length }
                return [string]::CompareOrdinal($a, $b) })
        $alt = [string]::Join('|', [string[]]@($names | ForEach-Object { [regex]::Escape($_) }))
        $namePattern = '(?<![\p{L}\p{N}])(?:' + $alt + ')(?![\p{L}\p{N}])'
        $regex = New-Object System.Text.RegularExpressions.Regex $namePattern, 'IgnoreCase, CultureInvariant'
        $alternatives.Add($namePattern)
    }
    # then the fixed patterns for names that are not in Lookup: an account SID always (both levels replace accounts),
    # the server of a UNC path only where the level replaces servers
    $alternatives.Add('(?<sid>' + $script:WorkerPerfMaskSidWord + ')')
    if ($script:WorkerPerfMaskLevelKinds[[string]$Mask.Level] -contains 'server') { $alternatives.Add($script:WorkerPerfMaskUncServer) }
    $other = ''
    if ($Mask.ContainsKey('Other')) { $other = [string]$Mask['Other'] }
    $Mask['Entries'] = $entries
    # a name of the name list wins over an identical protected name (P2-R9): a person called like a manufacturer or a
    # service is replaced; a protected phrase that only contains the name keeps protecting it
    $Mask['Protected'] = [string[]]@($Protected | Where-Object { -not [string]::IsNullOrEmpty($_) -and -not $lookup.ContainsKey($_.ToLowerInvariant()) })
    $Mask['Lookup'] = $lookup
    $Mask['Regex'] = $regex
    # protected names with white space or a word delimiter, searched as whole phrases at every position (longer first),
    # so that overlapping occurrences are found too; a name hit inside one stays
    $phrases = [string[]]@($Mask['Protected'] | Where-Object { $_ -match '[\s\\/()\[\],;:"''<>|=]' })
    $phrasePattern = ''
    if ($phrases.Count -gt 0) {
        [Array]::Sort($phrases, [Comparison[string]] { param($a, $b)
                if ($a.Length -ne $b.Length) { return $b.Length - $a.Length }
                return [string]::CompareOrdinal($a, $b) })
        $phrasePattern = '(?=(?<p>(?<![\p{L}\p{N}])(?:' + [string]::Join('|', [string[]]@($phrases | ForEach-Object { [regex]::Escape($_) })) + ')(?![\p{L}\p{N}])))'
    }
    $addresses = [string[]]@($entries | Where-Object { [string]$_.Kind -eq 'address' } | ForEach-Object { [string]$_.Name })
    $Mask['Masker'] = New-Object WorkerPerf.ReportMasker ([string]::Join('|', $alternatives.ToArray()), $lookup, $Mask['Protected'], $other, $phrasePattern, $addresses)
}

function Hide-WorkerPerfReportText($Text, $Mask) {
    # A text with the names of the mask replaced: whole names, longer before shorter, without regard to case; a hit
    # whose word (bounded by white space and \ / ( ) [ ] , ; : " ' < > | =) is a protected name stays. Then an account
    # SID and (level Alles) a UNC server that are not in Lookup become the text of mask.other. $null stays $null.
    if ($null -eq $Text) { return $null }
    return $Mask.Masker.Hide([string]$Text)
}

function Protect-WorkerPerfReportData($Data, $Mask) {
    # The report data with its names masked, as a new structure (the input is not changed): dictionaries and custom
    # objects become ordered dictionaries, lists become arrays, strings are masked, a StringBuilder (pre-rendered series
    # of New-JsonSeries and New-JsonIntegers), numbers, booleans and times stay as they are. The report's own field
    # names and keyword values are not names (P2-R10): keys stay, except in $WorkerPerfMaskKeyedMaps, and the values of
    # $WorkerPerfMaskKeywordFields stay.
    return , $Mask.Masker.Protect($Data, [string[]]$script:WorkerPerfMaskKeyedMaps, [string[]]$script:WorkerPerfMaskKeywordFields)
}

function Get-WorkerPerfMaskItem($Record, [string]$Key) {
    # The value under a key of a report record; $null when the record is no dictionary or lacks the key.
    if ($Record -is [System.Collections.IDictionary] -and $Record.Contains($Key)) { return , $Record[$Key] }
    return $null
}

function Get-WorkerPerfMaskList($Record, [string]$Key) {
    # The dictionaries of the list under a key of a report record (nothing when it is missing or $null).
    $v = Get-WorkerPerfMaskItem $Record $Key
    foreach ($x in @($v)) { if ($x -is [System.Collections.IDictionary]) { $x } }
}

function Clear-WorkerPerfMaskField($Records, [string]$Key) {
    # Sets the key to '' in each record that has it with a value that is not $null (a missing key or $null stays).
    foreach ($r in $Records) { if ($r -is [System.Collections.IDictionary] -and $r.Contains($Key) -and $null -ne $r[$Key]) { $r[$Key] = '' } }
}

function Clear-WorkerPerfMaskIncident($Incident) {
    # The message texts of an incident's events and of the events of its patterns (pattern companion).
    Clear-WorkerPerfMaskField @(Get-WorkerPerfMaskList $Incident 'events') 'text'
    foreach ($p in @(Get-WorkerPerfMaskList (Get-WorkerPerfMaskItem $Incident 'event') 'patterns')) {
        Clear-WorkerPerfMaskField @(Get-WorkerPerfMaskList (Get-WorkerPerfMaskItem $p 'detail') 'events') 'text'
    }
}

# What Protect-WorkerPerfReportData leaves as it is (P2-R10: the report's own field names and keyword values are not
# names). A field is named by its key ("kind": everywhere) or by the key of the record that holds it and its own key
# ("procs.role": the role of a record under procs, also incidents[].contributors.cpu.procs[]); list levels do not count.
# Dictionaries whose keys come from the recorded data (a map keyed by user, client, server ...): only their keys are
# masked. The report data has none today: every key is a field name of the code (contributors is keyed by resource).
$script:WorkerPerfMaskKeyedMaps = @()
# Fields whose value is always an identifier the code or the configuration files give, never a name or a server text.
$script:WorkerPerfMaskKeywordFields = @(
    'type', 'kind', 'group', 'log', 'lead', 'resource', 'resources', 'measure', 'scope', 'status', 'direction', 'isolation',
    'endReason', 'metric', 'signalId', 'id', 'day', 'capped', 'worker', 'snapKind',
    'sourceErrors.source', 'citrix.source', 'procs.role', 'apps.role', 'delayProcs.role')

function Clear-WorkerPerfReportFreeText($Data) {
    # Empties, in place, the texts of the report data that come from the server as they are and may hold names the
    # evaluation does not know: event messages (events, incidents and lookback incidents with the events of their
    # patterns, lookback near), command lines, the first error message of a failed source call, the end message, and
    # the detail of a source that is not available (and of its row in sollIst), which carries the reason of the failed
    # check. Texts the evaluation composes itself stay (they are masked by name). A missing key or $null stays.
    $meta = Get-WorkerPerfMaskItem $Data 'meta'
    Clear-WorkerPerfMaskField @($meta) 'endMessage'
    $quality = Get-WorkerPerfMaskItem $Data 'quality'
    Clear-WorkerPerfMaskField @(Get-WorkerPerfMaskList $quality 'sourceErrors') 'firstMessage'
    $unavailable = @{}
    foreach ($s in @(Get-WorkerPerfMaskList $quality 'sources')) {
        if ($s.Contains('available') -and $false -eq $s['available']) { $unavailable[[string]$s['id']] = $true; Clear-WorkerPerfMaskField @($s) 'detail' }
    }
    Clear-WorkerPerfMaskField @(Get-WorkerPerfMaskList $Data 'sollIst' | Where-Object { $unavailable.ContainsKey([string](Get-WorkerPerfMaskItem $_ 'id')) }) 'detail'
    Clear-WorkerPerfMaskField @(Get-WorkerPerfMaskList $Data 'procs') 'cmd'
    Clear-WorkerPerfMaskField @(Get-WorkerPerfMaskList $Data 'events') 'text'
    foreach ($inc in @(Get-WorkerPerfMaskList $Data 'incidents')) { Clear-WorkerPerfMaskIncident $inc }
    $before = Get-WorkerPerfMaskItem $Data 'before'
    Clear-WorkerPerfMaskField @(Get-WorkerPerfMaskList $before 'near') 'text'
    foreach ($inc in @(Get-WorkerPerfMaskList $before 'incidents')) { Clear-WorkerPerfMaskIncident $inc }
}
