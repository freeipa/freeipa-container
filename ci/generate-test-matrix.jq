
def repeat_array($n):
	. as $v | range($n) | $v
;

def frequency_to_list:
	. as $in
	| keys[]
	| . as $k
	| range($in[.])
	| $k
;

def random_select($count):
	if $count <= 0 or length <= 0 then empty
	else
		.[ now * 1000000 % length ] as $row
		| (. - [ $row ] | random_select($count - 1)),
			$row
	end
;

.["build-os"] as $os
| (.["fresh-os"] // []) as $fresh
| (if $ARGS.named["count"] != null then $ARGS.named["count"] | tonumber else .[ $ARGS.named["job"] ].count end) as $count
| if $ARGS.named["job"] == "run"
then
	.run as { "runs-on": $runson, $runtime, $readonly, $ca, $volume }
	| [ {
		"os": ($fresh | repeat_array(3), $os)[],
		"runs-on": $runson | frequency_to_list,
		"runtime": $runtime | frequency_to_list,
		"readonly": $readonly | frequency_to_list,
		"ca": $ca | frequency_to_list,
		"volume": $volume | frequency_to_list
	} ]
else if $ARGS.named["job"] == "test-upgrade"
then
	.["test-upgrade"] as { "runs-on": $runson, $runtime, $volume, "upgrade-to-from": $upgrade }
	| [ {
		"os": (($fresh | repeat_array(3), $os) | map(select(in($upgrade))))[],
		"runs-on": $runson | frequency_to_list,
		"runtime": $runtime | frequency_to_list
	}
	| .["data-from"] = $upgrade[.os][]
	]
else if $ARGS.named["job"] == "k3s"
then
	.k3s as { "runs-on": $runson }
	| [ {
		"os": ($fresh | repeat_array(3), $os)[]
	} ]
else
	error("Unknown job")
end
end
end
| [ random_select($count) | if ( .os as $os | $fresh | any(. == $os) ) then .["fresh-image"] = true end ]
| sort_by(.os, .["runs-on"], .runtime, .readonly, .ca, .volume, .["data-from"])

