ifndef BASE
	BASE=.
endif

run=grunt --base $(BASE) --gruntfile node_modules/pixbi-build/Gruntfile.coffee

# Dev mode by default
default:
	NODE_ENV=dev $(run) dev

# Installs Makefile symlink and gitignore
install:
	cp -f node_modules/pixbi-build/gitignore .gitignore
	ln -s node_modules/pixbi-build/Makefile Makefile

patch: prebuild build
	$(run) bump:patch
	make commit

minor: prebuild build
	$(run) bump:minor
	make commit

major: prebuild build
	$(run) bump:major
	make commit

build:
	$(run) build

# Separated from `build` for flexibility
prebuild:
	git stash
	git checkout develop

commit:
	# Update `component.js`
	$(run) updateComponent
	# Commit
	git add component.json
	git commit -m 'Bump version'
	# Merge into master
	git checkout master
	# Always force the new changes
	git merge develop -X theirs
	# Apply tag
	$(run) tag
	# Sync with Github
	git push origin develop:develop
	git push origin master:master
	git push origin --tags
	# Go back to develop
	git checkout develop
