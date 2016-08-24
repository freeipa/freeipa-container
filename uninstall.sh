#!/bin/bash

# Copyright 2016 Jan Pazdziora
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Uninstallation for atomic uninstall.

set -e

if [ -z "$DATADIR" -o -z "$HOST" ] ; then
	echo "Not sure where FreeIPA data is stored." >&2
	exit 1
fi

TARGET=$( date '+%Y%m%d-%H%M%S' )
mv "$HOST/$DATADIR" "$HOST/$DATADIR.backup.$TARGET"
echo "Moved [$DATADIR] aside to [$DATADIR.backup.$TARGET]."

exit 0
