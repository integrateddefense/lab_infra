#! /usr/bin/env bash

blocked='(^|/)vault|\.key$|\.pem$|\.pfx$'

while read old new ref; do
	git diff --name-only "$old" "$new" | grep -E "$blocked" > /dev/null && {
		echo "Push rejected: matched sensitive path/pattern"
		exit 1
	}
done
exit 0
