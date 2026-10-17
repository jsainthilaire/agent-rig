# Merge validated records onto shipped defaults; retain explicit settings only.
BEGIN { FS = OFS = "\t" }
FNR == NR {
    order[++count] = $1
    models[$1] = $2
    efforts[$1] = $3
    next
}
$1 == provider {
    id = $2 SUBSEP $3
    if ($4 == "default") { delete values[id]; delete origins[id] }
    else { values[id] = $4; origins[id] = $5 }
}
END {
    for (i = 1; i <= count; i++) {
        role = order[i]
        model_id = role SUBSEP "model"
        effort_id = role SUBSEP "effort"
        model = (model_id in values) ? values[model_id] : models[role]
        effort = (effort_id in values) ? values[effort_id] : efforts[role]
        if (provider == "claude") {
            if (model ~ /^claude-haiku-/ && effort != "omit") {
                print "Model configuration: " role ": Haiku requires effort = omit" > "/dev/stderr"
                bad = 1
            }
            if (model !~ /^claude-haiku-/ && efforts[role] == "omit" && !(effort_id in values)) {
                print "Model configuration: " role ": select an explicit effort or omit for " model > "/dev/stderr"
                bad = 1
            }
        }
        if (model_id in values || effort_id in values) {
            print "[" provider "." role "]" > overrides
            if (model_id in values) print "model = " model > overrides
            if (effort_id in values) print "effort = " effort > overrides
            print "" > overrides
        }
        print role, model, effort, ((model_id in origins) ? origins[model_id] : "default"), ((effort_id in origins) ? origins[effort_id] : "default")
    }
    if (bad) exit 1
}
