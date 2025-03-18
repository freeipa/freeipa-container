
def th($rowspan; $colspan):
	.[]
	| "      " + "<th"
		+ (if $rowspan > 1 then " rowspan=\"" + ($rowspan | tostring) + "\"" else "" end)
		+ (if $colspan > 1 then " colspan=\"" + ($colspan | tostring) + "\"" else "" end)
		+ ">"
		+ .
		+ "</th>"
;

def td($rowspan):
	.[]
	| "      " + "<td"
		+ (if $rowspan > 1 then " rowspan=\"" + ($rowspan | tostring) + "\"" else "" end)
		+ ">"
		+ .
		+ "</td>"
;

def build_dist_list:
	$ARGS.named["build-dist"] // [{ "os": "fedora-rawhide", "arch": "x86_64" }]
;

def os_grouping:
	{
	"^fedora-": "Fedora",
	"^centos-(.+)-stream$": "CentOS Stream",
	"^almalinux-": "AlmaLinux",
	"^rocky-": "Rocky Linux"
	}
;

def dist_group:
	(
	[
		.[].os as $os
		| os_grouping
		| reduce keys[] as $k ([$os, "", $os];
			if $os | test($k)
				then . = [$k, os_grouping[$k],
					($os | match($k) | .captures[0].string // $os[(.offset + .length):])]
			end)
	]
	| reduce .[] as $r ([]; if $r[0] == .[-1][0] then .[-1][2] += [ $r[2] ] else . + [[ $r[0], $r[1], [ $r[2] ]]] end)
	|
	(
		.[]
		| . as $r
		| [.[1]]
		| th(if $r[2][0] == "" then 2 else 1 end; $r[2] | length)
	),
	"    </tr>",
	"    <tr>",
	(
		.[][2]
		| reduce .[] as $n ([];
			if $n == "" then .
			else
				if $n == .[-1][1]
				then .[-1][0] += 1
				else . += [[1, $n]]
				end
			end)
		| .[]
		| .[0] as $colspan | [ .[1] ] | th(1; $colspan)
	)
	),
	"    </tr>",
	"    <tr>",
	(
		[ .[].arch | .[0:1] ] | th(1; 1)
	)
;

(
.[0]
|
if $ARGS.named["job"] == "legend"
	then "---",
		"Legend: "
			+ "🟢 — new image, compared to the one in registry; "
			+ "🔷 — test is run with image that matches one in registry; "
			+ "🔶 — test is run for image that does not get pushed to registry",
		halt
	else empty
end,
"## " + if $ARGS.named["job"] == "run"
		then "Test master + replica"
	elif $ARGS.named["job"] == "test-upgrade"
		then "Test upgrade from older installation"
	elif $ARGS.named["job"] == "k8s"
		then "Test in Kubernetes"
	end,
"<table>",
"  <thead>",
"    <tr>",
	(
	if $ARGS.named["job"] == "run" then [ "Runtime", "Readonly", "External CA", "Volume", "Runs on Ubuntu" ]
	elif $ARGS.named["job"] == "test-upgrade" then [ "Runtime", "Runs on Ubuntu", "Upgrade from" ]
	elif $ARGS.named["job"] == "k8s" then [ "Kubernetes", "Runtime", "Runs on Ubuntu" ]
	else empty end
	| th(3; 1)
	),
	( build_dist_list | dist_group ),
"    </tr>",
"  </thead>",
"  <tbody>"
),

(
.[]["runs-on"]? |= if . == null then empty else sub("^ubuntu-"; "") end
| .[].readonly? |= if . == null then empty else if . == "--read-only" then "yes (ro)" else "rw" end end
| .[].ca? |= if . == null then empty else if . == "--external-ca" then "external" else "no" end end
| .[].volume? |= if . == null then empty else if . == "freeipa-data" then "volume" else "dir" end end
| sort_by(.kubernetes, .runtime, .readonly, .ca, .volume, -(.["runs-on"] // 0 | tonumber), .["data-from"])
| [ .[] | .status = if .nopush then "nopush" else if .["fresh-image"] then "fresh-image" else false end end ]
| reduce .[] as $row ({};
	if $ARGS.named["job"] == "run"
	then .[ $row.runtime ][ $row.readonly ][ $row.ca ][ $row.volume ][ $row["runs-on"] ][ $row.os ][ $row.arch ] = $row.status
	elif $ARGS.named["job"] == "test-upgrade"
	then .[ $row.runtime ][ $row["runs-on"] ][ $row[ "data-from" ] ][ $row.os ][ $row.arch ] = $row.status
	elif $ARGS.named["job"] == "k8s"
	then .[ $row.kubernetes ][ $row.runtime ][ $row["runs-on"] ][ $row.os ][ $row.arch ] = $row.status
	end
)
| walk(if type == "object"
	then
		if ([.[][".arches"]?] | length) > 0 or ([.[][".rowspan"]?] | length) > 0
		then .[".rowspan"] = ([ .[][".rowspan"]? ] | add // 1)
		else .[".arches"] = true
		end
	else .
	end)
| . as $data
| [ path(.. | select(type == "object" and has(".rowspan"))) | select(length > 0)]
| (.[-1] | length) as $max
| foreach .[] as $i ([]; [$i, ($data | getpath($i)), (.[0] | length)])
| if (.[0] | length) == 1 or .[2] >= (.[0] | length) then "    <tr>" else empty end,

	(.[1][".rowspan"] as $rowspan | [ .[0][-1] ] | td($rowspan)),
	(
	if .[0] | length == $max then
		.[1] as $values
		| build_dist_list[] as $os
		| [ if ($values | has($os.os)) and ($values[$os.os] | has($os.arch)) then
			if $values[$os.os][$os.arch] == "fresh-image" then "🟢"
			elif $values[$os.os][$os.arch] == "nopush" then "🔶"
			else "🔷" end
			else "" end ] | td(1)
	else empty end
	),

if (.[0] | length) == $max then "    </tr>" else empty end
),

(
.[0]
|
"  </tbody>",
"</table>",
""
)

