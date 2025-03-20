
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
				( $ensure[$k] | keys[ now * 1000000 % length ] ) as $kk
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
		| [ to_entries[] | [ .key, .value ] ] as $ensure_delpaths
		| $row,
			($in - [ $row ] | random_select($count - 1; $ensure | delpaths( $ensure_delpaths ) | del(..|select(. == {}))))

	end
;

.["build-os"] as $os
| (.push.exclude // []) as $nopush
| ((.["fresh-os"] // []) - $nopush) as $fresh
| (if $ARGS.named["count"] != null then $ARGS.named["count"] | tonumber else .[ $ARGS.named["job"] ].count end) as $count
| if $ARGS.named["job"] == "run"
then
	.run as { "runs-on": $runson, $runtime, $readonly, $ca, $volume, $exclude }
	| [
		(.run | .os[(if $fresh | length > 0 then $fresh else $os end)[]] = 1),
		[ {
		"os": ($fresh | repeat_array(3), $os)[],
		"runs-on": $runson | frequency_to_list,
		"runtime": $runtime | frequency_to_list,
		"readonly": $readonly | frequency_to_list,
		"ca": $ca | frequency_to_list,
		"volume": $volume | frequency_to_list
		}
		| select([. | xcontains(($exclude // [])[])] | any | not)
		]
	]
elif $ARGS.named["job"] == "test-upgrade"
then
	.["test-upgrade"] as { "runs-on": $runson, $runtime, $volume, "upgrade-to-from": $upgrade, $exclude }
	| [
		(
		.["test-upgrade"]
		| .["data-from"][(.["upgrade-to-from"][$fresh[]] // [])[]] = 1
		| del(.["upgrade-to-from"])
		| .os[((if $fresh | length > 0 then $fresh else $os end) | map(select(in($upgrade))))[]] = 1
		),
		[ {
		"os": (($fresh | repeat_array(3), $os) | map(select(in($upgrade))))[],
		"runs-on": $runson | frequency_to_list,
		"runtime": $runtime | frequency_to_list
		}
		| .["data-from"] = $upgrade[.os][]
		| select([. | xcontains(($exclude // [])[])] | any | not)
		]
	]
elif $ARGS.named["job"] == "k8s"
then
	.k8s as { "runs-on": $runson, $kubernetes, $runtime, $exclude }
	| [
		(.k3s | .os[(if $fresh | length > 0 then $fresh else $os end)[]] = 1),
		[ {
		"os": ($fresh | repeat_array(3), $os)[],
		"runs-on": $runson | frequency_to_list,
		"kubernetes": $kubernetes | frequency_to_list,
		"runtime": $runtime | frequency_to_list
		}
		| select([. | xcontains(($exclude // [])[])] | any | not)
		]
	]
else
	error("Unknown job")
end
| .[0] as $ensure
| [
	.[1] | random_select($count; $ensure | del((..|nulls), (.[]|scalars), (.[]|arrays)))
		 | if ( .os as $os | $fresh | any(. == $os) ) then .["fresh-image"] = true end
		 | if ( .os as $os | $nopush | any(. == $os) ) then .["nopush"] = true end
]
| sort_by(.os, .["runs-on"], .kubernetes, .runtime, .readonly, .ca, .volume, .["data-from"])

