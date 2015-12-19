Package.describe({
  summary: "Reactive publish endpoints",
  version: '0.1.2',
  name: 'peerlibrary:reactive-publish',
  git: 'https://github.com/peerlibrary/meteor-reactive-publish.git'
});

Package.onUse(function (api) {
  api.versionsFrom('METEOR@1.0.3.1');

  // Core dependencies.
  api.use([
    'coffeescript',
    'underscore',
    'mongo'
  ], 'server');

  // 3rd party dependencies.
  api.use([
    'peerlibrary:server-autorun@0.5.1',
    'peerlibrary:reactive-mongo@0.1.1'
  ], 'server');

  api.addFiles([
    'publish.js',
    'server.coffee'
  ], 'server');
});

Package.onTest(function (api) {
  // Core dependencies.
  api.use([
    'coffeescript',
    'insecure',
    'random',
    'underscore',
    'reactive-var',
    'check'
  ]);

  // Internal dependencies.
  api.use([
    'peerlibrary:reactive-publish'
  ]);

  // 3rd party dependencies.
  api.use([
    'peerlibrary:assert@0.2.5',
    'peerlibrary:server-autorun@0.5.1',
    'peerlibrary:classy-test@0.2.20'
  ]);

  api.add_files([
    'tests.coffee'
  ]);
});
