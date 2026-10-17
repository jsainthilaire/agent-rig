# Parse user data without evaluating shell, INI interpolation, or native syntax.
function reject(message) {
    print "Model configuration: " FILENAME ":" FNR ": " message > "/dev/stderr"
    exit 1
}
function trim(value) {
    sub(/^[ \t]+/, "", value)
    sub(/[ \t]+$/, "", value)
    return value
}
function validate(p, role, key, value) {
    if (p !~ /^(codex|claude)$/) reject("unknown provider: " p)
    if (role !~ /^(explorer|implementer|database|tester|reviewer|debugger|security)$/) reject("unknown role: " role)
    if (key !~ /^(model|effort)$/) reject("unknown setting: " key)
    if (value == "default") return
    if (key == "model") {
        if (value == "inherit" || value !~ /^[a-zA-Z0-9][a-zA-Z0-9._:+\/-]*$/) reject("invalid model ID: " value)
    } else if (value !~ /^(low|medium|high|xhigh|max)$/ && !(p == "claude" && value == "omit")) {
        reject("invalid effort: " value)
    }
}
{
    sub(/\r$/, "")
    if (records) {
        count = split($0, fields, "\t")
        if (count != 4) reject("invalid override record")
        p = fields[1]; role = fields[2]; key = fields[3]; value = fields[4]
    } else {
        line = trim($0)
        if (line == "" || line ~ /^[#;]/) next
        if (line ~ /^\[/) {
            if (line !~ /^\[(codex|claude)\.[a-z_]+\]$/) reject("invalid section: " line)
            section = substr(line, 2, length(line) - 2)
            if (sections[section]++) reject("duplicate section: " section)
            split(section, parts, ".")
            p = parts[1]; role = parts[2]
            validate(p, role, "model", "default")
            next
        }
        if (!section) reject("setting outside a section")
        separator = index(line, "=")
        if (!separator) reject("expected key = value")
        key = trim(substr(line, 1, separator - 1))
        value = trim(substr(line, separator + 1))
    }
    validate(p, role, key, value)
    if (seen[p SUBSEP role SUBSEP key]++) reject("duplicate setting: " p "." role "." key)
    print p "\t" role "\t" key "\t" value
}
