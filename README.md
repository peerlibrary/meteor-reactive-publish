reactive-publish
================

This Meteor smart package extends [publish endpoints](http://docs.meteor.com/#/full/meteor_publish)
with support for reactivity so that you can use
[server-side autorun](https://github.com/peerlibrary/meteor-server-autorun) inside a publish function.
 
After adding this package you can use server-side [Tracker.autorun](http://docs.meteor.com/#/full/tracker_autorun)
inside your publish function and any published documents will be automatically correctly send to the client while your
reactive computation will rerun when any dependency triggers invalidation. Only changes to documents between reruns
will be send to the client. As a rule, things work exactly as you would expect, just reactively if they are inside an `autorun`.
You can use any source of reactivity, like [reactive server-side MongoDB queries](https://github.com/peerlibrary/meteor-reactive-mongo)
and reactive variables.

Publish function's `this` is extended with `this.autorun` which behaves the same as `Tracker.autorun`, but you can
return a cursor of array of cursors you want to publish. Moreover, computation is automatically stopped when subscription
is stopped. If you use `Tracker.autorun` you have to take care of this yourselves.

Server side only.

Installation
------------

```
meteor add peerlibrary:reactive-publish
```

Examples
--------

You can make a simple publish across an one-to-many relation:

```javascript
Meteor.publish('subscribed-posts', function () {
  this.autorun(function (computation) {
    var user = User.findOne(this.userId, {fields: {subscribedPosts: 1}});
    
    return Posts.find({_id: {$in: user && user.subscribedPosts || []}});
  });
});
```

You can make queries which are based on time:

```javascript
var currentTime = new ReactiveVar(new Date().valueOf());

Meteor.setInterval(function () {
  currentTime.set(new Date().valueOf());
}, 1000); // ms

Meteor.publish('recent-posts', function () {
  this.autorun(function (computation) {
    return Posts.find({
      timestamp: {
        $exists: true,
        $gte: currentTime.get() - (60 * 1000) // ms
      }
    }, {
      sort: {
        timestamp: 1
      }
    });
  });
});
```

You can make complicated but reactive permission checks. For example, support user groups:

```javascript
Meteor.publish('posts', function () {
  this.autorun(function (computation) {
    var user = User.findOne(this.userId, {fields: {groups: 1}});
    
    return Posts.find({
      $or: [{
        'access.userId': user && user._id
      }, {
        'access.groupId': {
          $in: user && user.groups || []
        }
      }]
    });
  });
});
```

Warnings
--------

Adding this package to your [Meteor](http://www.meteor.com/) application will make all MongoDB queries
reactive by default (you can still specify [`reactive: false`](http://docs.meteor.com/#/full/find) to
queries to disable reactivity for a specific query, or use
[`Tracker.nonreactive`](http://docs.meteor.com/#/full/tracker_nonreactive)). It will also automatically enable
[server-side autorun](https://github.com/peerlibrary/meteor-server-autorun). All this might break some existing
server-side code which might not expect to be reactive.

While documents are send to the client only once and in later reruns of computations only changes are send,
the server side still has to make a new query and compute a diff what to send for every rerun, so this approach
is suitable for reactivity which is not common, but you still want to support it. For example, queries with
reactive permission checks often will not change during the life-time of a query because permissions change rarely.
But if they do, a user will see results reactively.

Consider also optimizing your `autorun`s by splitting them into multiple `autorun`s or by nesting them. You can
also use [computed fields](https://github.com/peerlibrary/meteor-computed-field) to minimize propagation of
reactive change.

When using this approach to support reactive joins it is most suitable for one-to-many relations, where the "one" document
changes infrequently. For many-to-many joins consider publishing collections separately and join them on the client side.
The issue is that for any change for the first "many" documents, the computation will be invalidated and rerun to
query for second set of "many" documents. Alternatively, you can consider using [PeerDB](https://github.com/peerlibrary/meteor-peerdb)
which effectively denormalizes joins across many-to-many relations and allows direct querying and publishing.

Feel free to make pull requests with optimizations.

Acknowledgments
---------------

This package is based on the great work by [Diggory Blake](https://github.com/Diggsey/meteor-reactive-publish)
who made the first implementation.

Related projects
----------------

There are few other similar projects trying to address similar features, but theirs APIs are cumbersome and are different
than what developers are used to for Meteor.

* [meteor-publish-with-relations](https://github.com/tmeasday/meteor-publish-with-relations) – complicated custom API not
  allowing to reuse existing publish functions, which means no support for custom publish with `added`/`changed`/`removed`,
  no support for other reactive sources
* [meteor-smart-publish](https://github.com/yeputons/meteor-smart-publish) – complicated way of defining dependencies
  and works only with query cursors and not custom `added`/`changed`/`removed` functions or other reactive sources
* [reywood:publish-composite](https://github.com/englue/meteor-publish-composite) – allow you to define a nested structure
  of cursors, which get documents from higher levels in a reactive manner, but it works only with only with query cursors
  and not custom `added`/`changed`/`removed` functions or other reactive sources
* [copleyjk:simple-publish](https://github.com/copleykj/meteor-simple-publish) – seems similar to
  `meteor-publish-with-relations`, but a more developed version covering more edge cases; on the other hand it
  has the same limitations of no support for `added`/`changed`/`removed` or other reactive sources
* [peerlibrary:related](https://github.com/peerlibrary/meteor-related) – our previous implementation with different API
  and no reactivity support, but with support for custom `added`/`changed`/`removed` publishing
