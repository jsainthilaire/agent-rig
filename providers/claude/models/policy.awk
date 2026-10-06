# Provider-local policy validation. Never evaluate policy text as shell code.
BEGIN { FS = "\t" }
function reject(message) {
    print "Claude model policy: " message > "/dev/stderr"
    bad = 1
    exit 1
}
/^[[:space:]]*$/ || /^#/ { next }
$1 == "version" {
    if (NF != 2 || $2 != "1" || ++versions != 1) reject("unsupported or duplicate version")
    next
}
$1 == "reviewed" {
    if (NF != 2 || $2 !~ /^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/ || ++reviews != 1) reject("invalid review date")
    reviewed = $2
    next
}
$1 == "tier" {
    if (NF != 12 || $2 !~ /^(fast|balanced|strong|escalation)$/ || tier[$2]++) reject("invalid or duplicate tier")
    if ($3 !~ /^claude-(haiku|sonnet|opus|fable)-[0-9]+(-[0-9]+)*$/ || $3 ~ /-(latest|thinking)$/) reject("expected a pinned model ID")
    if ($3 ~ /^claude-(haiku|sonnet|opus)-(3-|4-[0-5]($|-))/ && $3 !~ /-[0-9]{8}$/) reject("pre-4.6 models require a dated snapshot")
    if (model[$3]++) reject("tiers must use distinct models")
    if ($4 !~ /^(-|low|medium|high|xhigh|max)$/) reject("invalid effort")
    if ($3 ~ /^claude-haiku-/ && $4 != "-") reject("Haiku does not support configurable effort")
    if ($3 !~ /^claude-haiku-/ && $4 == "-") reject("specify effort for reasoning models")
    for (i = 5; i <= 9; i++) if ($i !~ /^[0-9]+([.][0-9]+)?$/ || $i + 0 <= 0) reject("invalid pricing")
    if ($10 !~ /^[0-9]+$/ || $10 + 0 <= 0) reject("invalid context capacity")
    if ($11 !~ /^[0-9]{4}-(0[1-9]|1[0-2])$/ || $12 !~ /^(fastest|fast|moderate|slower)$/) reject("invalid model metadata")
    tier_count++
    tiers[$2] = $0
    next
}
$1 == "role" {
    if (NF != 5 || $2 !~ /^(explorer|implementer|database|tester|reviewer|debugger|security)$/ || role[$2]++) reject("invalid or duplicate role")
    if ($3 !~ /^(fast|balanced|strong)$/ || $4 !~ /^(balanced|strong|escalation)$/) reject("invalid role tier")
    if ($5 !~ /^0[.][0-9]+$|^1([.]0+)?$/ || $5 + 0 <= 0 || $5 + 0 > 1) reject("invalid quality threshold")
    defaults[$2] = $3
    next_tier[$2] = $4
    role_count++
    roles[$2] = $0
    next
}
{ reject("unknown record") }
END {
    if (bad) exit 1
    if (versions != 1 || reviews != 1 || tier_count != 4 || role_count != 7) reject("missing required records")
    split("fast balanced strong escalation", order, " ")
    split("explorer implementer database tester debugger reviewer security", names, " ")
    for (i = 1; i <= 7; i++) {
        name = names[i]
        expected = (name == "explorer" ? "fast" : (name == "reviewer" || name == "security" ? "strong" : "balanced"))
        if (defaults[name] != expected) reject("role default contradicts tier strategy")
        expected_next = (expected == "fast" ? "balanced" : (expected == "balanced" ? "strong" : "escalation"))
        if (next_tier[name] != expected_next) reject("escalation must move one tier at a time")
    }
    print "version\t1"
    print "reviewed\t" reviewed
    for (i = 1; i <= 4; i++) print tiers[order[i]]
    for (i = 1; i <= 7; i++) print roles[names[i]]
}
