#Requires -Version 5.1
# WorkerPerf report masking: collects the names of a whole capture and assigns their replacement names, then replaces
# them in texts and in the finished report data (definitions only).
# Requires WorkerPerf.Common.ps1, WorkerPerf.Load.ps1 (Open-WorkerPerfCsvReader), WorkerPerf.EventConfig.ps1 (default
# lists of accounts and domains that are not persons) and WorkerPerf.Events.ps1 (event and print driver readers, person check).
# Separate from the masking of the probe script Test-WorkerPerfSources.ps1, which is not used here.
# Get-WorkerPerfMaskRows, Get-WorkerPerfMaskHolders and Get-WorkerPerfMaskVocabularyHits emit plain pipeline output:
# wrap calls in @(...).

# kinds of names that each level replaces
$script:WorkerPerfMaskLevelKinds = @{
    Personen = @('user', 'client', 'sid')
    Alles    = @('user', 'client', 'sid', 'server', 'share', 'domain', 'address', 'printer')
}

# The three lists that must follow the report data (tests/MaskCensus.json names every string field of the report data and
# is checked against them). A field is named by its path in the report data (list levels as []), or, in the two lists of
# Protect-WorkerPerfReportData, by its key ("kind": everywhere) or by the key of the record that holds it and its own
# key ("procs.role": the role of a record under procs, also incidents[].contributors.cpu.procs[]); list levels do not count.
# (1) Texts copied from the server as they are, which may hold names the evaluation does not know: emptied by
# Clear-WorkerPerfReportFreeText. "?unavailable": only in a record whose id names a source that is not available (the
# detail then carries the reason of the failed check; the detail of an available source is a fixed text of the collector).
$script:WorkerPerfMaskFreeTextFields = @(
    'meta.endMessage', 'quality.sourceErrors[].firstMessage', 'quality.sources[].detail?unavailable', 'sollIst[].detail?unavailable',
    'procs[].cmd', 'events[].text', 'incidents[].events[].text', 'incidents[].event.patterns[].detail.events[].text',
    'before.near[].text', 'before.incidents[].events[].text', 'before.incidents[].event.patterns[].detail.events[].text')
# (2) Dictionaries whose keys come from the recorded data (a map keyed by user, client, server ...): only their keys are
# masked (P2-R10: the report's own field names are not names). The report data has none today: every key is a field
# name of the code (contributors is keyed by resource).
$script:WorkerPerfMaskKeyedMaps = @()
# (3) Fields whose value is always an identifier, unit or link the code or the configuration files give, never a name or
# a server text: their values stay (unit and url hold only values of thresholds.json, P2-R12).
$script:WorkerPerfMaskKeywordFields = @(
    'type', 'kind', 'group', 'log', 'lead', 'resource', 'resources', 'measure', 'scope', 'status', 'direction', 'isolation',
    'endReason', 'metric', 'signalId', 'id', 'day', 'capped', 'worker', 'snapKind', 'unit', 'url',
    'sourceErrors.source', 'citrix.source', 'procs.role', 'apps.role', 'delayProcs.role')

$script:WorkerPerfMaskIpv4Text = '(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)'
$script:WorkerPerfMaskIpv4 = New-Object System.Text.RegularExpressions.Regex ('^' + $script:WorkerPerfMaskIpv4Text + '$')
$script:WorkerPerfMaskSid = New-Object System.Text.RegularExpressions.Regex '^S-1-5-21-\d+-\d+-\d+-\d+$', 'IgnoreCase'
# folders under <drive>:\Users that belong to no person (wildcards, compared without regard to case): the shared
# folders, the temporary profile Windows creates when a profile cannot be loaded (TEMP, TEMP.<domain>, TEMP.<domain>.001),
# the accounts of the setup (defaultuser0 ...) and the folders of IIS application pools
$script:WorkerPerfMaskProfileFolders = @('Public', 'Default', 'Default User', 'All Users', 'TEMP', 'TEMP.*', 'defaultuser[0-9]*',
    '*AppPool', '.NET v*')
# The server of a UNC path: letters, digits, '-', '_' and '.', neither starting nor ending with a full stop (so not the
# device prefixes \\?\ and \\.\, and not the full stop or bracket that follows it in a sentence).
$script:WorkerPerfMaskServerText = '(?<server>[\p{L}\p{N}_-](?:[\p{L}\p{N}_.-]*[\p{L}\p{N}_-])?)'
# Fixed patterns in path and instance texts, scanned left to right: an account SID; a UNC path with its server (a WebDAV
# suffix @SSL and @<port> is not part of it) and, when present, its share (\\server\share); a user folder <drive>:\Users\<name> (any drive, any case), and the user of a
# Citrix UPM mount path \Users\<user>_UPM_local (also without drive).
# A SID may be joined to a name by '_' (FSLogix folders <SID>_<user>, <user>_<SID>). In a text the share ends at white
# space; in a field that holds nothing but a path (process path, volume, event object) it runs to the next backslash, so
# that a share name with a space (\\fs01\Abteilung Kardiologie) is one name.
$script:WorkerPerfMaskPathPatternText = '(?<sid>(?<![\p{L}\p{N}-])S-1-5-21-\d+-\d+-\d+-\d+(?![\p{L}\p{N}-]))' +
    '|(?<unc>\\\\' + $script:WorkerPerfMaskServerText + '(?:@SSL)?(?:@\d{1,5})?\\(?<share>[^\\/\s,;"*:|<>]+)?)' +
    '|(?<drive>(?<![A-Za-z])[A-Za-z]:)?\\Users\\(?<folder>[^\\]+?)(?<upm>_UPM_local)?(?=\\|$)'
$script:WorkerPerfMaskPathPatterns = New-Object System.Text.RegularExpressions.Regex $script:WorkerPerfMaskPathPatternText, 'IgnoreCase'
$script:WorkerPerfMaskPathFieldPatterns = New-Object System.Text.RegularExpressions.Regex ($script:WorkerPerfMaskPathPatternText.Replace(
        '(?<share>[^\\/\s,;"*:|<>]+)', '(?<share>[^\\/,;"*:|<>]+)')), 'IgnoreCase'
# a folder name that joins an account SID and a name with '_' (FSLogix): the name is a user
$script:WorkerPerfMaskSidFolder = New-Object System.Text.RegularExpressions.Regex ('^(?:S-1-5-21(?:-\d+){4}_(?<name>.+)|(?<name>.+?)_S-1-5-21(?:-\d+){4})$'), 'IgnoreCase'
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
        private readonly Regex designations;
        private readonly Dictionary<string, bool> designationWords;
        private readonly Dictionary<string, bool> persons;
        private readonly Dictionary<string, bool> addresses;
        // the report data repeats most of its strings (keys, kinds, users, applications): each is replaced once
        private readonly Dictionary<string, string> done = new Dictionary<string, string>(StringComparer.Ordinal);
        private const int DoneLimit = 200000;

        // pattern: alternatives of the names (no group), an unknown SID (group sid) and a UNC server (group server).
        // lookup: lower-case (invariant) name -> replacement; protectedNames: names that stay; other: the replacement
        // of a SID or UNC server that is not in lookup. phrasePattern: the protected names that hold white space or a
        // word delimiter, as one pattern with group p at every position (null or empty without such names).
        // addresses: the names of kind address. The designations the customer wrote (endpoint designations, role labels)
        // shield only names of a person (persons: the names of kind user, client and sid, P2-R13): designationWords, the
        // designations that are one word, keep a person name inside that word; designationPattern, like phrasePattern,
        // keeps a person name inside a designation with white space or a delimiter where it is part of a longer word.
        public ReportMasker(string pattern, IDictionary lookup, string[] protectedNames, string other, string phrasePattern, string[] addresses,
            string[] designationWords, string designationPattern, string[] persons)
        {
            this.designationWords = ToSet(designationWords, true);
            this.persons = ToSet(persons, true);
            if (!string.IsNullOrEmpty(phrasePattern))
            {
                this.phrases = new Regex(phrasePattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
            }
            if (!string.IsNullOrEmpty(designationPattern))
            {
                this.designations = new Regex(designationPattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
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
            List<int> named = null;
            if (!this.lookup.TryGetValue(text.ToLowerInvariant(), out rep))
            {
                rep = this.pattern.Replace(text, delegate(Match m) { return this.Evaluate(text, m, ref spans, ref named); });
            }
            if (this.done.Count < DoneLimit) { this.done[text] = rep; }
            return rep;
        }

        // spans, named: the occurrences of protected phrases and of designations in text (start, end pairs), found on the
        // first name hit
        private string Evaluate(string text, Match m, ref List<int> spans, ref List<int> named)
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
            if (IsProtected(this.protectedNames, text, m.Index, m.Length)) { return m.Value; }
            if (InSpan(this.phrases, text, m.Index, m.Length, ref spans)) { return m.Value; }
            if (this.persons.ContainsKey(m.Value.ToLowerInvariant()))
            {
                if (IsProtected(this.designationWords, text, m.Index, m.Length)) { return m.Value; }
                if (!IsWholeWord(text, m.Index, m.Length) && InSpan(this.designations, text, m.Index, m.Length, ref named)) { return m.Value; }
            }
            if (this.addresses.Count > 0 && this.addresses.ContainsKey(m.Value.ToLowerInvariant()) && InDottedNumber(text, m.Index, m.Length)) { return m.Value; }
            if (this.lookup.TryGetValue(m.Value.ToLowerInvariant(), out rep)) { return rep; }
            return m.Value;
        }

        // The hit lies completely inside an occurrence of a phrase of the pattern ("Nexus KIS" keeps a user nexus).
        private static bool InSpan(Regex phrases, string text, int index, int length, ref List<int> spans)
        {
            if (phrases == null) { return false; }
            if (spans == null)
            {
                spans = new List<int>();
                foreach (Match p in phrases.Matches(text))
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

        // The hit is a word of its own: bounded by the start or end of the text or by a word delimiter (full stops at its
        // end do not count: the end of a sentence). "fs01" in "Dateiserver fs01" is, "oracle" in "Oracle-Listener" is not.
        private static bool IsWholeWord(string text, int index, int length)
        {
            if (index > 0 && !IsDelimiter(text[index - 1])) { return false; }
            int b = index + length;
            while (b < text.Length && text[b] == '.') { b++; }
            return b >= text.Length || IsDelimiter(text[b]);
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
        private static bool IsProtected(Dictionary<string, bool> names, string text, int index, int length)
        {
            if (names.Count == 0) { return false; }
            int a = index;
            while (a > 0 && !IsDelimiter(text[a - 1])) { a--; }
            int b = index + length;
            while (b < text.Length && !IsDelimiter(text[b])) { b++; }
            string word = text.Substring(a, b - a).ToLowerInvariant();
            if (names.ContainsKey(word)) { return true; }
            string trimmed = word.TrimEnd('.');
            return trimmed.Length > 0 && trimmed.Length < word.Length && names.ContainsKey(trimmed);
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
            return ToSet(names, false);
        }

        private static Dictionary<string, bool> ToSet(string[] names, bool lower)
        {
            Dictionary<string, bool> set = new Dictionary<string, bool>(StringComparer.Ordinal);
            if (names != null) { foreach (string n in names) { if (!string.IsNullOrEmpty(n)) { set[lower ? n.ToLowerInvariant() : n] = true; } } }
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
    $seen = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
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

function Add-WorkerPerfMaskName($State, [string]$Kind, [string]$Name, $AliasOf = $null) {
    # Takes a name once (without regard to case), in the spelling and at the place of its first appearance; an empty
    # name is passed over. A name already taken keeps its kind, except that user, client and sid (replaced in both
    # levels) win over the kinds only level Alles replaces: a client that is also an endpoint host is a client; and a
    # second name of a server (-AliasOf: the record of the name it stands for) yields to any later kind. Numbers are given
    # at the end, in the order of the names, per kind; a second name takes the number of its record. Returns the record.
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $n = $Name.Trim()
    $key = $n.ToLowerInvariant()
    $rec = $State.Seen[$key]
    if ($null -ne $rec) {
        $person = $script:WorkerPerfMaskLevelKinds['Personen']
        if ($null -ne $rec.AliasOf -and $rec.Kind -ne $Kind -and $null -eq $AliasOf) { $rec.Kind = $Kind; $rec.AliasOf = $null }
        elseif ($person -contains $Kind -and $person -notcontains $rec.Kind) { $rec.Kind = $Kind; $rec.AliasOf = $null }
        return $rec
    }
    $rec = @{ Kind = $Kind; Name = $n; AliasOf = $AliasOf }
    $State.Seen[$key] = $rec
    $State.Records.Add($rec)
    return $rec
}

function Add-WorkerPerfMaskProtected($State, [string]$Name, [switch]$Designation) {
    # A name that stays: process, service, application, module, driver and manufacturer names; -Designation: a designation
    # the customer wrote (endpoint designation, role label), which keeps no name that stands in it as a word of its own.
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $n = $Name.Trim()
    $key = $n.ToLowerInvariant()
    if ($Designation) { $list = $State.Designations; $seen = $State.DesignationSeen } else { $list = $State.Protected; $seen = $State.ProtectedSeen }
    if ($seen.ContainsKey($key)) { return }
    $seen[$key] = $true
    $list.Add($n)
}

function Add-WorkerPerfMaskHost($State, [string]$HostName) {
    # A host: an IPv4 address, else a server name (leading backslashes of an SMB server name dropped). Of a server name
    # with more than one label after the host (fs01.sim.local), the DNS suffix (sim.local) is a domain and the first
    # label (fs01) a second name of the same server with the same replacement, unless that label is a word of the
    # report's own texts ("proxy") or already a name of another kind (P2-R13).
    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    $h = $HostName.Trim().TrimStart('\')
    if ($script:WorkerPerfMaskIpv4.IsMatch($h)) { [void](Add-WorkerPerfMaskName $State 'address' $h); return }
    $before = $State.Records.Count
    $rec = Add-WorkerPerfMaskName $State 'server' $h
    $dot = $h.IndexOf('.')
    if ($dot -gt 0 -and $h.IndexOf('.', $dot + 1) -gt $dot + 1 -and -not $h.EndsWith('.')) {
        $label = $h.Substring(0, $dot)
        $known = $State.Seen[$label.ToLowerInvariant()]
        if ($rec.Kind -eq 'server' -and $null -eq $rec.AliasOf) {
            if ($null -eq $known) {
                if ($label.Length -gt 1 -and -not $State.Vocabulary.ContainsKey($label.ToLowerInvariant())) { [void](Add-WorkerPerfMaskName $State 'server' $label $rec) }
            }
            elseif ($State.Records.Count -gt $before -and $known.Kind -eq 'server' -and $null -eq $known.AliasOf) {
                # the short name came first: the new full name takes its replacement
                $rec.AliasOf = $known
            }
        }
        [void](Add-WorkerPerfMaskName $State 'domain' $h.Substring($dot + 1))
    }
}

function Add-WorkerPerfMaskUncName($State, [string]$Kind, [string]$Name) {
    # A share or printer name, then the server of its UNC path (\\server\..., a WebDAV suffix @SSL and @<port> is not
    # part of it) when it has one.
    [void](Add-WorkerPerfMaskName $State $Kind $Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $m = [regex]::Match($Name.Trim(), '^\\\\' + $script:WorkerPerfMaskServerText + '(?:@SSL)?(?:@\d{1,5})?\\', 'IgnoreCase')
    if ($m.Success) { Add-WorkerPerfMaskHost $State $m.Groups['server'].Value }
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
    if ($script:WorkerPerfMaskSid.IsMatch($name)) { [void](Add-WorkerPerfMaskName $State 'sid' $name); return }
    if (-not $CheckPerson) { [void](Add-WorkerPerfMaskName $State 'user' $name) }
    elseif (Test-WorkerPerfMaskVirtualDomain $State $dom) { return }
    elseif (Test-WorkerPerfEventPersonUser $name $State.EventConfig) { [void](Add-WorkerPerfMaskName $State 'user' $name) }
    elseif ($name.Length -gt 1 -and $name.EndsWith('$')) { Add-WorkerPerfMaskHost $State $name.Substring(0, $name.Length - 1) }
    else { return }
    [void](Add-WorkerPerfMaskName $State 'domain' $dom)
}

function Get-WorkerPerfMaskFolderUser($State, [string]$Folder) {
    # The account of a profile folder under <drive>:\Users (P2-R3, P2-R14): $null for a folder of no person
    # (WorkerPerfMaskProfileFolders); <name>.<domain>, <name>.<domain>.NNN and <name>.NNN (the folders Windows creates when
    # a folder of that name exists) are the user <name>, where <domain> is a domain the capture names; else the folder.
    foreach ($p in $script:WorkerPerfMaskProfileFolders) { if (Test-WorkerPerfAccountPattern $Folder $p) { return $null } }
    $m = [regex]::Match($Folder, '^(?<name>.+?)\.(?<domain>[^.]+)(?:\.\d{3})?$')
    if ($m.Success) {
        $known = $State.Seen[$m.Groups['domain'].Value.ToLowerInvariant()]
        if ($null -ne $known -and $known.Kind -eq 'domain') { return $m.Groups['name'].Value }
    }
    $m = [regex]::Match($Folder, '^(?<name>.+)\.\d{3}$')
    if ($m.Success) { return $m.Groups['name'].Value }
    return $Folder
}

function Add-WorkerPerfMaskPatternNames($State, [string]$Text, [System.Text.RegularExpressions.Regex]$Patterns) {
    # The names the fixed patterns find in a text, in their order in the text.
    if ([string]::IsNullOrEmpty($Text)) { return }
    foreach ($m in $Patterns.Matches($Text)) {
        if ($m.Groups['sid'].Success) { [void](Add-WorkerPerfMaskName $State 'sid' $m.Groups['sid'].Value) }
        elseif ($m.Groups['unc'].Success) {
            if ($m.Groups['share'].Success) { [void](Add-WorkerPerfMaskName $State 'share' ($m.Groups['unc'].Value)) }
            Add-WorkerPerfMaskHost $State $m.Groups['server'].Value
        }
        elseif ($m.Groups['upm'].Success) { Add-WorkerPerfMaskAccount $State $m.Groups['folder'].Value '' $true }
        elseif ($m.Groups['drive'].Success) {
            $user = Get-WorkerPerfMaskFolderUser $State $m.Groups['folder'].Value
            if ($null -ne $user) { Add-WorkerPerfMaskAccount $State $user '' $true }
        }
        elseif ($m.Groups['ip'].Success) { [void](Add-WorkerPerfMaskName $State 'address' $m.Groups['ip'].Value) }
    }
    # a folder that joins an account SID and a name (FSLogix <SID>_<user>, <user>_<SID>): the name is a user
    foreach ($segment in $Text.Split([char[]]@('\', '/'))) {
        $f = $script:WorkerPerfMaskSidFolder.Match($segment)
        if ($f.Success) { Add-WorkerPerfMaskAccount $State $f.Groups['name'].Value '' $true }
    }
}

function Get-WorkerPerfMaskVocabulary([hashtable]$Texts) {
    # The words of the report's own texts (texts.de.json), lower-case: a first label of a host that is one of them is no
    # second server name.
    $words = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    if ($null -eq $Texts) { return , $words }
    foreach ($v in $Texts.Values) {
        foreach ($w in [regex]::Split([string]$v, '[^\p{L}\p{N}]+')) { if ($w.Length -gt 0) { $words[$w.ToLowerInvariant()] = $true } }
    }
    return , $words
}

function New-WorkerPerfMask {
    # The names of a whole capture (never a time cut, so every report of one capture uses the same replacements) and their
    # replacement names. Files are read in a fixed order, each from its first line on; the order of first appearance
    # decides the numbers. The numbers do not depend on the level: Personen keeps the numbers of Alles.
    # Returns @{ Level; Entries = @{ Kind; Name; Replacement }[] of the level, in order of first appearance;
    # Protected = string[] of names that must stay (process, service, application, module, driver and manufacturer names);
    # Designations = string[] of the endpoint designations and role labels; Shadowed = protected names equal to a name of
    # the level; Lookup = lower-case name -> replacement; Regex = one pattern of all names of the level,
    # longer before shorter, whole names only, without regard to case ($null without names) }.
    # -EventConfig: from Read-WorkerPerfEventConfig (NonPersonAccounts, NonPersonDomains); without it the built-in lists.
    param([string]$Path, [ValidateSet('Personen', 'Alles')][string]$Level, [hashtable]$Texts, [string[]]$RoleLabels = @(), $EventConfig = $null)
    if ($null -eq $EventConfig) {
        $EventConfig = @{ NonPersonAccounts = $script:WorkerPerfDefaultNonPersonAccounts; NonPersonDomains = $script:WorkerPerfDefaultNonPersonDomains }
    }
    # ordinal tables (their keys are lower-case already): Windows PowerShell's @{} compares by the current culture
    $st = @{ Seen = (New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)); Records = (New-Object System.Collections.Generic.List[object])
        Protected = (New-Object System.Collections.Generic.List[string]); ProtectedSeen = (New-Object System.Collections.Hashtable ([StringComparer]::Ordinal))
        Designations = (New-Object System.Collections.Generic.List[string]); DesignationSeen = (New-Object System.Collections.Hashtable ([StringComparer]::Ordinal))
        EventConfig = $EventConfig; Vocabulary = (Get-WorkerPerfMaskVocabulary $Texts) }

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
        [void](Add-WorkerPerfMaskName $st 'client' $r[2])
        $winStations.Add($r[3])
    }
    # (2a) citrix.csv: an ICA instance "<WinStation> (<domain>\<user>)" or "<WinStation> (<user>)" names its user, which
    # may hold brackets itself ("ICA-CGP 7 (Meier (Extern))"): everything between the first opening and the last bracket
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'citrix.csv' @('Instance'))) {
        $m = [regex]::Match($r[0], '^([^()]*?)\s*\((.*)\)\s*$')
        if ($m.Success) { Add-WorkerPerfMaskAccount $st $m.Groups[2].Value '' $false }
    }
    # (3) shares.csv, (4) volumes.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'shares.csv' @('Share'))) { Add-WorkerPerfMaskUncName $st 'share' $r[0] }
    $volumes = @(Get-WorkerPerfMaskRows $Path 'volumes.csv' @('Volume', 'Backing'))
    # the backing of a profile container is a share or a whole path on it (\\fs01\fslogix\<SID>_<user>\x.vhdx): its share
    # and server come from the UNC prefix, its user from the path patterns below (step 8)
    foreach ($r in $volumes) {
        $m = [regex]::Match($r[1].Trim(), '^\\\\' + $script:WorkerPerfMaskServerText + '(?:@SSL)?(?:@\d{1,5})?\\[^\\/]+', 'IgnoreCase')
        if ($m.Success) { Add-WorkerPerfMaskUncName $st 'share' $m.Value }
    }
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

    # (8) fixed patterns: in the fields that hold nothing but a path or a name (procinfo.csv Path, volumes.csv Volume and
    # Backing, the name fields of the events: User, Printer, Object, App, Module), then sessions.csv WinStation, then with
    # addresses the free texts of meta.json (source details and error messages). Not the event Text: it never reaches a
    # masked report.
    $procs = @(Get-WorkerPerfMaskRows $Path 'procinfo.csv' @('Name', 'Path', 'Services'))
    $pathTexts = New-Object System.Collections.Generic.List[string]
    foreach ($r in $procs) { $pathTexts.Add($r[1]) }
    foreach ($r in $volumes) { $pathTexts.Add($r[0]); $pathTexts.Add($r[1]) }
    foreach ($ev in $events) { foreach ($c in 'User', 'Printer', 'Object', 'App', 'Module') { $pathTexts.Add([string]$ev[$c]) } }
    foreach ($t in $pathTexts) { Add-WorkerPerfMaskPatternNames $st $t $script:WorkerPerfMaskPathFieldPatterns }
    foreach ($t in $winStations) { Add-WorkerPerfMaskPatternNames $st $t $script:WorkerPerfMaskPathPatterns }
    $freeTexts = New-Object System.Collections.Generic.List[string]
    $sources = Get-WorkerPerfField $meta 'Sources'
    if ($null -ne $sources) { foreach ($p in $sources.PSObject.Properties) { $freeTexts.Add([string](Get-WorkerPerfField $p.Value 'Detail')) } }
    $errors = Get-WorkerPerfField $meta 'SourceErrors'
    if ($null -ne $errors) { foreach ($p in $errors.PSObject.Properties) { $freeTexts.Add([string](Get-WorkerPerfField $p.Value 'FirstMessage')) } }
    $freeTexts.Add([string](Get-WorkerPerfField $meta 'EndMessage'))
    foreach ($t in $freeTexts) { Add-WorkerPerfMaskPatternNames $st $t $script:WorkerPerfMaskTextPatterns }

    # names that stay; of an event's application and module only the file name (the field may hold a whole path, whose
    # user folder is a name)
    foreach ($r in $procs) {
        Add-WorkerPerfMaskProtected $st $r[0]
        foreach ($s in $r[2].Split(';')) { Add-WorkerPerfMaskProtected $st $s }
    }
    foreach ($ev in $events) {
        foreach ($c in 'App', 'Module') { $v = [string]$ev[$c]; Add-WorkerPerfMaskProtected $st $v.Substring($v.LastIndexOfAny([char[]]@('\', '/')) + 1) }
        foreach ($c in 'Service', 'Driver') { Add-WorkerPerfMaskProtected $st ([string]$ev[$c]) }
    }
    foreach ($d in @(Read-WorkerPerfPrintDrivers $Path)) { Add-WorkerPerfMaskProtected $st $d.Name; Add-WorkerPerfMaskProtected $st $d.Manufacturer }
    # the designations the customer wrote (P2-R13)
    foreach ($e in $endpoints) { Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Name')) -Designation; Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Role')) -Designation }
    foreach ($l in $RoleLabels) { Add-WorkerPerfMaskProtected $st $l -Designation }

    # numbers per kind in the order of the names (whatever the level), then the level's kinds; a second name of a server
    # takes the replacement of its record
    $numbers = @{}
    $all = New-Object System.Collections.Generic.List[object]
    $byRecord = New-Object 'System.Collections.Generic.Dictionary[object,string]'
    foreach ($rec in $st.Records) {
        $target = $rec.AliasOf
        if ($null -ne $target -and $target.Kind -eq $rec.Kind -and $byRecord.ContainsKey($target)) { $rep = $byRecord[$target] }
        else {
            $no = 1
            if ($numbers.ContainsKey($rec.Kind)) { $no = [int]$numbers[$rec.Kind] + 1 }
            $numbers[$rec.Kind] = $no
            $rep = ($Texts['mask.' + $rec.Kind] -f $no)
        }
        $byRecord[$rec] = $rep
        $all.Add(@{ Kind = $rec.Kind; Name = $rec.Name; Replacement = $rep })
    }
    $kinds = $script:WorkerPerfMaskLevelKinds[$Level]
    $entries = @($all | Where-Object { $kinds -contains $_.Kind })
    $mask = @{ Level = $Level; Other = [string]$Texts['mask.other'] }
    Set-WorkerPerfMaskNames -Mask $mask -Entries $entries -Protected ([string[]]$st.Protected.ToArray()) -Designations ([string[]]$st.Designations.ToArray())
    return $mask
}

function Get-WorkerPerfMaskPhrasePattern([string[]]$Phrases) {
    # The names that hold white space or a word delimiter, as one pattern searched at every position (longer first, so
    # that overlapping occurrences are found too) with group p; '' without such names.
    $list = [string[]]@($Phrases | Where-Object { $_ -match '[\s\\/()\[\],;:"''<>|=]' })
    if ($list.Count -eq 0) { return '' }
    [Array]::Sort($list, [Comparison[string]] { param($a, $b)
            if ($a.Length -ne $b.Length) { return $b.Length - $a.Length }
            return [string]::CompareOrdinal($a, $b) })
    return '(?=(?<p>(?<![\p{L}\p{N}])(?:' + [string]::Join('|', [string[]]@($list | ForEach-Object { [regex]::Escape($_) })) + ')(?![\p{L}\p{N}])))'
}

function Set-WorkerPerfMaskNames {
    # Sets the names of a mask (made by New-WorkerPerfMask, which calls this at its end): Entries = @{ Kind; Name;
    # Replacement }[]; Protected; Designations; Shadowed; Lookup = lower-case name -> replacement; Regex = one pattern of
    # all names, longer before shorter, whole names only, without regard to case ($null without names); Masker = the
    # replacer that Hide-WorkerPerfReportText and Protect-WorkerPerfReportData use. Uses Mask.Level and Mask.Other (the
    # text of mask.other). Changes the mask in place and returns nothing.
    param($Mask, [object[]]$Entries = @(), [string[]]$Protected = @(), [string[]]$Designations = @())
    if (-not ('WorkerPerf.ReportMasker' -as [type])) { Add-Type -TypeDefinition $script:WorkerPerfMaskSource -Language CSharp }
    $entries = @($Entries | Where-Object { $null -ne $_ })
    $lookup = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
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
    # a name of the name list wins over an identical protected name or designation (P2-R9): a person called like a
    # manufacturer or a service is replaced; a protected phrase that only contains the name keeps protecting it. A
    # designation that is also a protected name protects as one.
    $isName = { param($n) -not [string]::IsNullOrEmpty($n) -and $lookup.ContainsKey($n.ToLowerInvariant()) }
    $Mask['Protected'] = [string[]]@($Protected | Where-Object { -not [string]::IsNullOrEmpty($_) -and -not (& $isName $_) })
    $kept = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    foreach ($p in $Mask['Protected']) { $kept[$p.ToLowerInvariant()] = $true }
    $Mask['Designations'] = [string[]]@($Designations | Where-Object { -not [string]::IsNullOrEmpty($_) -and -not (& $isName $_) -and -not $kept.ContainsKey($_.ToLowerInvariant()) })
    $Mask['Shadowed'] = [string[]]@($Protected | Where-Object { & $isName $_ })
    $Mask['Lookup'] = $lookup
    $Mask['Regex'] = $regex
    # a designation shields only the names of a person (P2-R13): one that is one word like a protected name (the hit then
    # is part of that word); one with white space or a delimiter where the hit is part of a longer word. The names only
    # level Alles replaces (server, share, domain, address, printer) are replaced in a designation wherever they stand.
    $designationWords = [string[]]@($Mask['Designations'] | Where-Object { $_ -notmatch '[\s\\/()\[\],;:"''<>|=]' })
    $phrasePattern = Get-WorkerPerfMaskPhrasePattern $Mask['Protected']
    $designationPattern = Get-WorkerPerfMaskPhrasePattern $Mask['Designations']
    $addresses = [string[]]@($entries | Where-Object { [string]$_.Kind -eq 'address' } | ForEach-Object { [string]$_.Name })
    $persons = [string[]]@($entries | Where-Object { $script:WorkerPerfMaskLevelKinds['Personen'] -contains [string]$_.Kind } | ForEach-Object { [string]$_.Name })
    $Mask['Masker'] = New-Object WorkerPerf.ReportMasker ([string]::Join('|', $alternatives.ToArray()), $lookup, [string[]]@($Mask['Protected']), $other, $phrasePattern,
        $addresses, $designationWords, $designationPattern, $persons)
}

function Get-WorkerPerfMaskVocabularyHits($Mask, [hashtable]$Texts, [string[]]$Units = @()) {
    # The replacement names (in the order of the entries, each once) of the names of the mask that equal a word of the
    # report's own vocabulary: the texts of texts.de.json, the units, and the protected names a name took over (P2-R9;
    # a designation equal to a name is meant to be replaced, P2-R13). Sentences with that word are garbled in the masked report and can give the name away (P2-R12).
    $hit = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    if ($null -ne $Mask.Regex) {
        $vocabulary = New-Object System.Collections.Generic.List[string]
        if ($null -ne $Texts) { foreach ($v in $Texts.Values) { $vocabulary.Add([string]$v) } }
        foreach ($u in $Units) { $vocabulary.Add([string]$u) }
        foreach ($v in $vocabulary) { foreach ($m in $Mask.Regex.Matches($v)) { $hit[$m.Value.ToLowerInvariant()] = $true } }
    }
    foreach ($s in @($Mask.Shadowed)) { if (-not [string]::IsNullOrEmpty($s)) { $hit[$s.ToLowerInvariant()] = $true } }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($Mask.Entries)) {
        if ($hit.ContainsKey(([string]$e.Name).ToLowerInvariant()) -and -not $out.Contains([string]$e.Replacement)) { $out.Add([string]$e.Replacement) }
    }
    $out.ToArray()
}

function Test-WorkerPerfMaskKnownAccount($Mask, [string]$Account) {
    # $true when an account name "<domain>\<name>", "<name>@<domain>" or "<name>" consists of names the mask replaces: the
    # name is a user of the mask, and a domain part is one of its names too, unless the level keeps domains.
    if ([string]::IsNullOrWhiteSpace($Account)) { return $false }
    $a = $Account.Trim(); $name = $a; $dom = ''
    $cut = $a.LastIndexOf('\'); $at = $a.LastIndexOf('@')
    if ($cut -ge 0) { $name = $a.Substring($cut + 1); $dom = $a.Substring(0, $cut) }
    elseif ($at -gt 0) { $name = $a.Substring(0, $at); $dom = $a.Substring($at + 1) }
    $user = @($Mask.Entries | Where-Object { [string]$_.Kind -eq 'user' -and [string]::Equals([string]$_.Name, $name, [StringComparison]::OrdinalIgnoreCase) })
    if ($user.Count -eq 0) { return $false }
    if ($dom -eq '' -or $script:WorkerPerfMaskLevelKinds[[string]$Mask.Level] -notcontains 'domain') { return $true }
    return $Mask.Lookup.ContainsKey($dom.ToLowerInvariant())
}

function Hide-WorkerPerfReportText($Text, $Mask) {
    # A text with the names of the mask replaced: whole names, longer before shorter, without regard to case; a hit
    # whose word (bounded by white space and \ / ( ) [ ] , ; : " ' < > | =) is a protected name stays, as does a hit inside
    # a protected phrase and a hit that is part of a longer word inside a designation. Then an account SID and (level
    # Alles) a UNC server that are not in Lookup become the text of mask.other. $null stays $null.
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

function Save-WorkerPerfMaskMap {
    # Writes the names of a mask and their replacements (the real names: the file must stay with the person who made the
    # report) as UTF-8 without BOM: { "level": ..., "entries": [ { "kind", "name", "replacement" } ] } in the order of
    # assignment. Overwrites an existing file.
    param($Mask, [string]$Path)
    $entries = @(@($Mask.Entries) | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{ kind = [string]$_.Kind; name = [string]$_.Name; replacement = [string]$_.Replacement } })
    $map = [ordered]@{ level = [string]$Mask.Level; entries = $entries }
    $json = ConvertTo-Json -InputObject $map -Depth 4
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Get-WorkerPerfMaskItem($Record, [string]$Key) {
    # The value under a key of a report record; $null when the record is no dictionary or lacks the key.
    if ($Record -is [System.Collections.IDictionary] -and $Record.Contains($Key)) { return , $Record[$Key] }
    return $null
}

function Get-WorkerPerfMaskHolders($Data, [string]$Path) {
    # The records that hold the last key of a field path of WorkerPerfMaskFreeTextFields ("incidents[].events[].text":
    # every event record of every incident). A missing key or $null on the way gives nothing.
    $nodes = @(, $Data)
    $steps = $Path.Split('.')
    for ($i = 0; $i -lt $steps.Length - 1; $i++) {
        $step = $steps[$i]
        $list = $step.EndsWith('[]')
        $key = $step.TrimEnd('[', ']')
        $next = New-Object System.Collections.Generic.List[object]
        foreach ($n in $nodes) {
            $v = Get-WorkerPerfMaskItem $n $key
            if ($list) { foreach ($x in @($v)) { if ($x -is [System.Collections.IDictionary]) { $next.Add($x) } } }
            elseif ($v -is [System.Collections.IDictionary]) { $next.Add($v) }
        }
        $nodes = $next.ToArray()
    }
    foreach ($n in $nodes) { if ($n -is [System.Collections.IDictionary]) { $n } }
}

function Clear-WorkerPerfReportFreeText($Data) {
    # Empties, in place, the texts of the report data that come from the server as they are and may hold names the
    # evaluation does not know: the fields of WorkerPerfMaskFreeTextFields (event messages, command lines, the first error
    # message of a failed source call, the end message, the detail of a source that is not available). Texts the
    # evaluation composes itself stay (they are masked by name). A missing key or $null stays.
    $unavailable = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    foreach ($s in @(Get-WorkerPerfMaskHolders $Data 'quality.sources[].id')) {
        if ($s.Contains('available') -and $false -eq $s['available']) { $unavailable[[string]$s['id']] = $true }
    }
    foreach ($field in $script:WorkerPerfMaskFreeTextFields) {
        $path = $field
        $onlyUnavailable = $field.EndsWith('?unavailable')
        if ($onlyUnavailable) { $path = $field.Substring(0, $field.Length - '?unavailable'.Length) }
        $key = $path.Substring($path.LastIndexOf('.') + 1)
        foreach ($r in @(Get-WorkerPerfMaskHolders $Data $path)) {
            if ($onlyUnavailable -and -not $unavailable.ContainsKey([string](Get-WorkerPerfMaskItem $r 'id'))) { continue }
            if ($r.Contains($key) -and $null -ne $r[$key]) { $r[$key] = '' }
        }
    }
}
