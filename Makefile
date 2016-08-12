
PHONY = check-branches

check-branches:
	for i in Dockerfile.* ; do \
		BRANCH=$${i#Dockerfile.} ; \
		echo "Checking $$i" ; \
		if git show $$BRANCH:Dockerfile > /dev/null 2>&1 ; then \
			git diff HEAD:$$i $$BRANCH:Dockerfile | cat ; \
			! git diff --numstat HEAD $$BRANCH | grep -E -v 'Dockerfile|Makefile' | grep . ; \
		elif git show origin/$$BRANCH:Dockerfile > /dev/null 2>&1 ; then \
			git diff HEAD:$$i origin/$$BRANCH:Dockerfile | cat ; \
			! git diff --numstat HEAD origin/$$BRANCH | grep -E -v 'Dockerfile|Makefile' | grep . ; \
		else \
			echo "    skipping, no branch $$BRANCH" ; \
		fi \
	done
