
def repeat_array($n):
	. as $v | range($n) | $v
;

def frequency_to_list:
	. as $in
	| keys[]
	| . // 1 as $k
	| range($in[.])
	| $k
;

def xcontains($element):
	. as $input |
	[ $element | to_entries | .[] | $input[.key] == .value ] | all
;

def random_select($count; $ensure):
	if $count <= 0 or length <= 0 then empty
	else
		. as $in
		|
		(
		if (($ensure != null) and ($ensure | length > 0))
		then
			[ foreach ($ensure | keys[]) as $k ({};
				( $ensure[$k] | .[ now * 1000000 % length ] ) as $kk
				| .[$k] = $kk;
				.
				),
				[]
			]
			| reverse
			| until(.[0] | length > 0;
				[ . as $dot
				| [ $in[] | select(xcontains($dot[1])) ]
				,
				$dot[2:][]])
			| .[0]
		end
		)
		| .[ now * 1000000 % length ]
		| . as $row
		| $row,
			($in - [ $row ] | random_select($count - 1; $row | to_entries | reduce .[] as $e ($ensure; if .[$e.key] then .[$e.key] -= [ $e.value ] end) | del(..|select(. == []))))

	end
;

.["build-dist"] as $dist
| (.push.exclude // []) as $nopush
| [(.["fresh-dist"] // []) | .[] | select([ xcontains($nopush[]) ] | any | not)] as $fresh
| if $ARGS.named["job"] == "push-data"
then
	[ [ $fresh[].os ] | unique[] | . as $os
		| { "os": $os, "arch": [ $dist | map(select(.os == $os)) | .[] | [ . ] | select(all(contains($nopush[]) | not)) | .[].arch ] } ]
elif $ARGS.named["job"] == "push"
then
	[ $fresh[].os ] | unique
else
(if $ARGS.named["count"] != null then $ARGS.named["count"] | tonumber else .[ $ARGS.named["job"] ].count end) as $count
| if $ARGS.named["job"] == "run"
then
	.run as { "runs-on": $runson, $runtime, $readonly, $ca, $volume, $exclude }
	| [
		.run | to_entries | reduce .[] as $e ({}; .[$e.key] |= ( $e.value | objects | keys ))
		| .dist |= [(if $fresh | length > 0 then $fresh else $dist end)[]],
		[ {
		"os": null, "arch": null,
		"dist": ($fresh | repeat_array(3), $dist)[],
		"runs-on": $runson | frequency_to_list,
		"runtime": $runtime | frequency_to_list,
		"readonly": $readonly | frequency_to_list,
		"ca": $ca | frequency_to_list,
		"volume": $volume | frequency_to_list
		}
		| . += .dist
		| select([. | xcontains(($exclude // [])[])] | any | not)
		]
	]
elif $ARGS.named["job"] == "test-upgrade"
then
	.["test-upgrade"] as { "runs-on": $runson, $runtime, $volume, "upgrade-to-from": $upgrade, $exclude }
	| [
		.["test-upgrade"] | to_entries | reduce .[] as $e ({};
			if $e.key == "upgrade-to-from"
			then .["data-from"] |= ([ $e.value[$fresh[].os] | arrays[]] | unique)
			else .[$e.key] |= ( $e.value | objects | keys )
			end)
		| .dist |= [((if $fresh | length > 0 then $fresh else $dist end) | .[] | select($upgrade[.os]))],
		[ {
		"os": null, "arch": null,
		"dist": (($fresh | repeat_array(3), $dist) | .[] | select($upgrade[.os])),
		"runs-on": $runson | frequency_to_list,
		"runtime": $runtime | frequency_to_list
		}
		| . += .dist
		| .["data-from"] = $upgrade[.os][]
		| select([. | xcontains(($exclude // [])[])] | any | not)
		]
	]
elif $ARGS.named["job"] == "k8s"
then
	.k8s as { "runs-on": $runson, $kubernetes, $runtime, $exclude }
	| [
		.k8s | to_entries | reduce .[] as $e ({}; .[$e.key] |= ( $e.value | objects | keys ))
		| .dist |= [(if $fresh | length > 0 then $fresh else $dist end)[]],
		[ {
		"os": null, "arch": null,
		"dist": ($fresh | repeat_array(3), $dist)[],
		"runs-on": $runson | frequency_to_list,
		"kubernetes": $kubernetes | frequency_to_list,
		"runtime": $runtime | frequency_to_list
		}
		| . += .dist
		| select([. | xcontains(($exclude // [])[])] | any | not)
		]
	]
else
	error("Unknown job")
end
| .[0] as $ensure
| [
	.[1] | random_select($count; $ensure | del(..|select(. == [])))
		| if ( .dist as $d | $fresh | any(. == $d) ) then .["fresh-image"] = true end
		| if ( .dist as $d | any($d | xcontains($nopush[])) ) then .["nopush"] = true end
		| del(.dist)
]
| sort_by(.os, .arch, .["runs-on"], .kubernetes, .runtime, .readonly, .ca, .volume, .["data-from"])

end

