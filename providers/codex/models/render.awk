# Rewrite native top-level settings only; preserve role instructions verbatim.
BEGIN { FS = "\t" }
FNR == NR {
    if ($1 == role) { model = $2; effort = $3 }
    next
}
/^developer_instructions = / {
    if (!model_seen && model != "inherit") print "model = \"" model "\""
    if (!effort_seen && effort != "inherit") print "model_reasoning_effort = \"" effort "\""
    instructions = 1
}
!instructions && /^model = / { model_seen = 1; if (model != "inherit") print "model = \"" model "\""; next }
!instructions && /^model_reasoning_effort = / { effort_seen = 1; if (effort != "inherit") print "model_reasoning_effort = \"" effort "\""; next }
{ print }
