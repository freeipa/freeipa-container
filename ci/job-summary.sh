#!/bin/bash

set -e

# To make debugging easier, we will output to stdout when run on terminal
[ -t 0 ] || exec >> $GITHUB_STEP_SUMMARY

if [ "$1" == --legend ] ; then
	echo ---
	echo 'Legend: 🟢 — new image, compared to the one in registry; 🔷 — test is run with image that matches one in registry'
	exit
fi

DIR="$1"
TITLE="$2"

cd $DIR

echo "## $TITLE"

LAST=$( find * -type d | tail -1 | sed 's%^.*/%%; s%=.*$%%' )
declare -A OS=(
    [fedora-]=Fedora
    [centos-9-stream]='CentOS Stream 9'
    [almalinux-]='AlmaLinux'
    [rocky-]='Rocky Linux'
)
cat <<EOS
<table>
  <thead>
    <tr>
EOS
find * -type d -name "$LAST=*" | head -1 | sed -E 's%=[^/]*(/|$)%\n%g; s%\n$%%' | sed 's%runs-on%runs-on Ubuntu%; s%^ca$%external CA%;' \
	| sed 's%^%      <th rowspan="2">%; s%$%</th>%'
declare -a OSNAMES=()
declare -a OSNAMES_COLSPAN=()
declare -a OSNAMES_ROWSPAN=()
declare -a OSRELEASES=()
while read r ; do
	for i in "${!OS[@]}" ; do
		if [ "${r#$i}" != "$r" ] ; then
			OSRELEASES+=("${r#$i}")
			ROWSPAN=1
			if [ -z "${OSRELEASES[-1]}" ] ; then
				ROWSPAN=2
			fi
			if [ ${#OSNAMES[@]} -gt 0 ] && [ "${OSNAMES[-1]}" == "${OS[$i]}" ] ; then
				OSNAMES_COLSPAN[-1]=$(( ${OSNAMES_COLSPAN[-1]} + 1 ))
				OSNAMES_ROWSPAN[-1]=$ROWSPAN
			else
				OSNAMES+=("${OS[$i]}")
				OSNAMES_COLSPAN+=(1)
				OSNAMES_ROWSPAN+=($ROWSPAN)
			fi
			break
		fi
	done
done < <( yq '.jobs.build.strategy.matrix.os[]' < ../.github/workflows/build-test.yaml )
for i in $( seq 0 $(( ${#OSNAMES_COLSPAN[@]} - 1 )) ) ; do
	echo -n '      <th'
	if [ ${OSNAMES_COLSPAN[$i]} != 1 ] ; then
		echo -n " colspan='${OSNAMES_COLSPAN[$i]}'"
	fi
	if [ ${OSNAMES_ROWSPAN[$i]} != 1 ] ; then
		echo -n " rowspan='${OSNAMES_ROWSPAN[$i]}'"
	fi
	echo ">${OSNAMES[$i]}</th>"
done
echo '    </tr>'
echo '    <tr>'
for v in "${OSRELEASES[@]}" ; do
	if [ -n "$v" ] ; then
		echo "      <th>$v</th>"
	fi
done
cat <<EOS
    </tr>
  </thead>
EOS

cat <<EOS
  <tbody>
EOS
prev_depth=999
while read d ; do
	depth=$( echo "$d" | sed 's%/%\n%g' | wc -l )
	if [ $depth -le $prev_depth ] ; then
		echo '    <tr>'
	fi
	prev_depth=$depth
	echo -n '      <td'
	rowspan=$( find "$d" -type d -name "$LAST=*" | wc -l )
	if [ $rowspan -ne 1 ] ; then
		echo -n " rowspan='$rowspan'"
	fi
	echo -n '>'
	echo "$d" | sed 's%=ubuntu-%=%; s%readonly=/%readonly=rw/%; s%readonly=--read-only%readonly=yes (ro)%; s%ca=/%ca=no/%; s%ca=--external-ca%ca=external%; s%volume=/%volume=dir/%; s%volume=freeipa-data%volume=volume%' | sed -Ez 's%^.*=%%; s%/\n%%'
	echo '</td>'
	if [[ "/$d" =~ "/$LAST=" ]] ; then
		yq '.jobs.build.strategy.matrix.os[]' < ../.github/workflows/build-test.yaml \
			| while read i ; do
				echo -n '      <td>'
				if test -f "$d/os=$i" ; then
					if test -f ../fresh-image/$i ; then
						echo -n '🟢'
					else
						echo -n '🔷'
					fi
				fi
				echo '</td>'
			done
		echo '    </tr>'
	fi
done < <( find * -type d | sed 's%$%/%' | LC_ALL=C sort )
cat <<EOS
  </tbody>
</table>
EOS
