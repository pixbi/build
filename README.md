# duplo

Intuitive, simple building blocks for building composable, completely
self-managed web applications


## Installation

    $ npm install -g duplo


## Usage

* `duplo new <name> <git-repo-url>` scaffolds a new duplo repo
* `duplo dev` starts a local server and re-compiles on file change
* `duplo build` runs a build. This could be used for checking the code against
  Closure Compiler.
* `duplo patch` builds the project and bump the patch version
* `duplo minor` builds the project and bump the minor version
* `duplo major` builds the project and bump the major version


## Philosophies

* Stay as close to raw JavaScript as possible, because JavaScript lacks the
  mechanism to build strong abstraction.
* Closures are discouraged. Optimally, there should be no function, anonymous
  or otherwise, nested within another function. A callback should be named
  explicitly to another static function.
* `this` is evil. Developers should not need to context-switch between
  functions. See [Context](#Context) for duplo's solution.
* One file contains one module that does one thing. I believe it is called the
  UNIX philosophy.

Ultimately, there is really just one guiding principle: Keep It Simple, Stupid.


## Technologies

* [Jade](http://jade-lang.com/) over HTML
* [Stylus](http://learnboost.github.io/stylus/) over CSS
* JavaScript


## File Structure

    app/            --> Application code
    app/index.jade  --> Entry point for templates. Only this file is compiled.
                        Use Jade's include system to pull in other templates.
    app/params.json --> Optional parameter object made available as
                        `module.params`
    app/assets/     --> Asset files are copied as-is to build's top-level
                        directory
    app/styl/       --> Any application style (see below for details)
    app/modules/    --> Module within the application that are included AFTER
                        code in the top-level `app/` directory when building
    components/     --> Other repos imported via Component.IO
    component.json  --> The Component.IO manifest
    dev/            --> Any code necessary to run the application in dev mode
    public/         --> Built files when developing. Not committed to source
    test/           --> Test files go here


## Development

During development, everything in the `dev/` directory is copied over as-is *at
the end* of the build process. This means that files in the directory would
replace whatever is built at their respective locations. The `index.html` in
`dev/` would need to reference the script and the tag manually, e.g.

    <html>
      <head>
        <link rel="stylesheet" href="style.css"/>
      </head>
      <body>
        <script src="script.js"></script>
      </body>
    </html>

The output file exposes the mode via the `module.mode` attribute. When in
development, `module.mode === 'dev'` should be `true`.


## Dependency Management

One declares a dependency by calling `require(2)`. It is not unlike CommonJS,
but the similarity ends there. There is neither `exports` nor `module`.
Instead, the `main()` function is always exported.

```js
// a.js
function main (x) {
  return x + 1;
}

// b.js
var a = require('a');

function main () {
  var out = a(3);

  return out + 1; // -> 4
}
```

### Module Path

There is actually something incomplete in the above example: the first
parameter to `require(2)` must be a "module path". The path consists of the
repo in which the module lives, as referenced by its Component.IO name,
followed by its path in its location relative to its module's `app/modules/`
directory.

For example, if the repo running duplo is `pixbi/war`, as per Component.IO
convention:

```js
// components/pixbi-nuclear-missile/app/modules/dod/pentagon/launch.js
function launch () {
  // World annihilation
}

function main (countdown) {
  setTimeout(launch, countdown);
}

// app/modules/white-house/president/declare-war.js
var launch = require('pixbi.nuclearMissile.dod.pentagon.launch');

function main () {
  launch(10000);
}

// app/index.js
var declare = require('pixbi.war.whiteHouse.president.declareWar');

function main () {
  declare();
}
```

Yes, it is relatively verbose to call another module. The point is to be
explicit as possible and to encourage shorter module names.

### Factory Pattern

The factory pattern is implemented at the module level to avoid having to
implement it at the application level, as it is a common pattern. This is to
simplify application development by offering only one way to do one thing.

A module is instantiated by specifying a name to `require(2)` as the second
parameter. Take the following example:

```js
// a.js
var x = 0;

function main (y) {
  x += y;

  return x;
}

// b.js
var a = require('user.repo.a', 'someName');

function main () {
  a(1); // -> 1
}

// c.js
var a = require('user.repo.a', 'someOtherName');

function main () {
  a(2); // -> 2
}

// d.js
var a = require('user.repo.a', 'someName');

function main () {
  a(3); // -> 4
}

// e.js
var a = require('user.repo.a');

function main () {
  a(4); // -> 4
}
```

Note that when the second parameter is absent, it is effectively "naming" the
instance as an empty string. In short, all modules are singletons by default
and optionally instantiable by name.

### Debugging

It may seem at first glance that this approach is effective a strict revealing
module pattern with only `main()` exposed, and so it should be difficult to
inspect the internals at run-time. However, in development mode, there is a
secret door into the instance.

You would call `require(3)` like so: `require('user.repo.a.b.c', '', true);` to
access the instance.  Likewise, a module variable `x` could be accessed as
`require('user.repo.a.b.c', '', true).x`. To access a named instance's
functions or variables, use `require('user.repo.a.b.c', 'an-instance-name',
true).x`.

Note that this is only available in development mode.


## Application Parameters

You may specify an optional `params.json`, the content of which would be
injected as `module.params`. For instance, with a `params.json` of:

```json
{
  "config": {
    "kickass": true
  }
}
```

`public/script.js` would look something like:

```js
...
module.mode = "dev";
module.params = {
  "config": {
    "kickass": true
  }
};
```

And we then may call it in `index.html` like this:

```html
<body>
  <script>
    document.addEventListener('DOMContentLoaded', function () {
      module.init(module.params);
    });
  </script>
</body>
```

The benefit of this is that we could place a `params.json` in `dev/` for dev
mode and one in `app/` for production and have a complete isolation between
code And configuration.


## CSS/Stylus Order

Where you place your CSS files within `app/` is significant. Stylus files will
be concatenated in this order:

    app/styl/variables.styl   --> An optional variable file that gets injected
                                  into every Stylus file
    app/styl/keyframes.styl   --> Keyframes
    app/styl/fonts.styl       --> Font declarations
    app/styl/reset.styl       --> Resetting existing CSS in the target
                                  environment
    app/styl/main.styl        --> Application CSS that goes before any module
                                  CSS
    app/modules/**/index.styl --> CSS relevant to specific modules


## Selective Exclusion

Some cases require the repo to be polymorphic in the sense that we could
generate different forms of the same codebase. For example, you may need to
build the repo in an embeddable form which would exclude certain dependencies
that are required in its standalone form. In this case you would include an
`exclude` attribute in the `component.json` manifest file. The `forms` object
then contains the `embeddable` and the `standalone` attributes, each of which
then contains an array of dependencies as specified in the `dependencies`
attribute to *exclude*.

Running `duplo build embeddable` would build without the specified dependencies
under `embeddable` while running `duplo build standalone` would do the same
with those specified under the `standalone` attribute. `duplo build` would
build with all dependencies.

Note that selective exclusion applies at the dependency level but not files in
the component.

An example of a `component.json`:

```json
{
  "dependencies": {
    "pixbi/sdk": "1.1.1",
    "pixbi/embeddable": "2.2.2",
    "pixbi/standalone": "3.3.3"
  },
  "exclude": {
    "embeddable": [
      "pixbi/standalone"
    ],
    "standalone": [
      "pixbi/embeddable"
    ]
  }
}
```


## In-Depth Explanation

The following sections are explanations for how it works. Feel free to skip if
the actual implementations do not bother you, although understanding how it
works helps with debugging by offering a mental model of where everything goes.

### Compiling

Compiling the project performs these steps:

1. Copy files in `app/assets/` to `public/`
2. Copy files in `dev/` to `public/`
3. `public/index.html` is created if it doesn't already exist
4. Compile all Stylus files (order specified [below](#cssstylus-order)) under
   `app/` and concatenate into one CSS file as `public/index.css`
5. Concatenate all JavaScript under `app/` into one JS file as
   `public/index.js`
6. Compile all Jade files under `app/` into one HTML file and inject into the
   end of `body` in `public/index.html`
7. Write into `public/index.html` tags to include `style.css` and `script.js`

Note that while compiling the builder creates a temporary `tmp/` directory.

### Building

Building the project performs these steps:

1.  Stash changes to git to avoid data loss (you should of course make sure
    there is no uncommitted code as well)
2.  Checkout the `develop` branch
3.  Compile the project
4.  Apply Closure Compiler with advanced optimizations on the built JavaScript.
    Any error would stop the process here and fixes should be applied before
    retrying.
5.  Apply any transformation for further uglification
6.  Scan through the `app/` directory and write all relevant file references to
    `components.json`
7.  Bump the respective version
8.  Commit to git
9.  Checkout the `master` branch and merge `develop` into `master`
10. Apply the new version as a new git tag
11. Checkout the `develop` branch again

### Dependency Resolution

AMD is used for dependency resolution; however, you do not need to use
`define(2)`. In fact, AMD is used during the build step and is completely
invisible to duplo users. So `define(2)` is actually not available.

### Context

Each module is actually just a function. It gets run after its dependencies
have been resolved. The `main()` function then becomes the only entry point
into the module.

Even though it feels as if `this` is bound to the module, that is not exactly
true. The context actually depends on the instance as named via `require(2)` in
order for the factory pattern as highlighted above to work.

All top-level functions within the module are "bound" to the current instance
of the module. This "binding" is not a "hard" bind using `bind()`. A rewrite is
performed at build-time to convert `this` references to a hygienic reference to
`this` of the module function. And all calls to bound functions (note: the only
free function should be `require(2)`) are called with that reference. In
addition, non-local variables (i.e. those which are top-level in the module)
are also rewritten to properties of the module function's `this`.

For the category-inclined, duplo modules are *loosely* applicative functors.
`require(2)` is analogous to `pure` in that it lifts the main module function
into an applicative and normal function calls thereafter are analogous to `<*>`
in that all calls to other module functions by `main()` are essentially
`fmap`ping.

And since all code is organized in modules in the duplo world, the entire
program is basically one big applicative functor.


## Copyright and License

Code and documentation copyright 2014 Pixbi. Code released under the MIT
license. Docs released under Creative Commons.
