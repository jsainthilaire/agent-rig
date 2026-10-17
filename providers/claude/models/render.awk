# Render only native model/effort frontmatter; retain the role's tools and body.
BEGIN { FS = "\t" }
function reject(message) {
    print "Claude agent renderer: " message > "/dev/stderr"
    bad = 1
    exit 1
}
FNR == NR {
    if ($1 == "tier") { models[$2] = $3; efforts[$2] = $4 }
    if ($1 == "role") role_tiers[$2] = $3
    if ($1 == "effective") { effective_models[$2] = $3; effective_efforts[$2] = $4 }
    next
}
FNR == 1 {
    if (!(role in role_tiers)) reject("missing role " role)
    if ($0 != "---") reject("missing opening frontmatter")
    header = 1
    print
    next
}
header && $0 == "---" {
    if (model_count != 1 || effort_count != 1) reject("model and effort must each consume the policy once")
    header = 0
    closed = 1
    print
    next
}
header && $0 == "model: __AGENT_RIG_MODEL__" {
    model_count++
    model = ((role in effective_models) ? effective_models[role] : models[role_tiers[role]])
    # Custom IDs that resemble YAML scalars must still be native strings.
    if (model ~ /^[0-9]/ || tolower(model) ~ /^(true|false|null|yes|no|on|off)$/) model = "\"" model "\""
    print "model: " model
    next
}
header && $0 == "effort: __AGENT_RIG_EFFORT__" {
    effort_count++
    effort = (role in effective_efforts) ? effective_efforts[role] : efforts[role_tiers[role]]
    if (effort != "-") print "effort: " effort
    next
}
header && $0 ~ /^(model|effort):/ { reject("model and effort must use provider placeholders") }
{ print }
END {
    if (bad) exit 1
    if (!closed) reject("missing closing frontmatter")
}
