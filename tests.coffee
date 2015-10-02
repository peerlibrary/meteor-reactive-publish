Users = new Meteor.Collection 'Users_meteor_reactivepublish_tests'
Posts = new Meteor.Collection 'Posts_meteor_reactivepublish_tests'
Addresses = new Meteor.Collection 'Addresses_meteor_reactivepublish_tests'
Fields = new Meteor.Collection 'Fields_meteor_reactivepublish_tests'

if Meteor.isServer
  Meteor.publish null, ->
    Users.find()

  Meteor.publish 'posts', (ids) ->
    Posts.find
      _id:
        $in: ids

  Meteor.publish 'users-posts', (userId) ->
    handle = Tracker.autorun (computation) =>
      user = Users.findOne userId,
        fields:
          posts: 1

      fields = Fields.findOne userId

      Posts.find(
        _id:
          $in: user?.posts or []
      ,
        fields: _.omit (fields or {}), '_id'
      ).observeChanges
        added: (id, fields) =>
          assert not Tracker.active
          fields.dummyField = true
          @added 'Posts_meteor_reactivepublish_tests', id, fields
        changed: (id, fields) =>
          assert not Tracker.active
          @changed 'Posts_meteor_reactivepublish_tests', id, fields
        removed: (id) =>
          assert not Tracker.active
          @removed 'Posts_meteor_reactivepublish_tests', id

      @ready()

    @onStop =>
      handle?.stop()
      handle = null

    return

  Meteor.publish 'users-posts-foreach', (userId) ->
    handle = Tracker.autorun (computation) =>
      user = Users.findOne userId,
        fields:
          posts: 1

      fields = Fields.findOne userId

      Posts.find(
        _id:
          $in: user?.posts or []
      ,
        fields: _.omit (fields or {}), '_id'
      ).forEach (document, i, cursor) =>
        fields = _.omit document, '_id'
        fields.dummyField = true
        @added 'Posts_meteor_reactivepublish_tests', document._id, fields

      @ready()

    @onStop =>
      handle?.stop()
      handle = null

    return

  Meteor.publish 'users-posts-and-addresses', (userId) ->
    @autorun (computation) =>
      user1 = Users.findOne userId,
        fields:
          posts: 1

      Posts.find(
        _id:
          $in: user1?.posts or []
      )

    @autorun (computation) =>
      user2 = Users.findOne userId,
        fields:
          addresses: 1

      Addresses.find(
        _id:
          $in: user2?.addresses or []
      )

    return

  Meteor.publish 'users-posts-and-addresses-together', (userId) ->
    @autorun (computation) =>
      user = Users.findOne userId,
        fields:
          posts: 1
          addresses: 1

      [
        Posts.find(
          _id:
            $in: user?.posts or []
        )
      ,
        Addresses.find(
          _id:
            $in: user?.addresses or []
        )
      ]

    return

  Meteor.publish 'users-posts-count', (userId, countId) ->
    @autorun (computation) =>
      user = Users.findOne userId,
        fields:
          posts: 1

      count = 0
      initializing = true

      Posts.find(
        _id:
          $in: user?.posts or []
      ).observeChanges
        added: (id) =>
          assert not Tracker.active
          count++
          @changed 'Counts', countId, count: count unless initializing
        removed: (id) =>
          assert not Tracker.active
          count--
          @changed 'Counts', countId, count: count unless initializing

      initializing = false

      @added 'Counts', countId,
        count: count

      @ready()

    return

  currentTime = new ReactiveVar new Date().valueOf()

  Meteor.setInterval ->
    currentTime.set new Date().valueOf()
  , 50 # ms

  Meteor.publish 'recent-posts', ->
    @autorun (computation) =>
      timestamp = currentTime.get() - 2000 # ms

      Posts.find(
        timestamp:
          $exists: true
          $gte: timestamp
      ,
        sort:
          timestamp: 1
      )

    return

  # We use our own insert method to not have latency compensation so that observeChanges
  # on the client really matches how databases changes on the server.
  Meteor.methods
    'insertPost': (timestamp) ->
      check timestamp, Number

      Posts.insert
        timestamp: timestamp

class ReactivePublishTestCase extends ClassyTestCase
  @testName: 'reactivepublish'

  setUpServer: ->
    # Initialize the database.
    Users.remove {}
    Posts.remove {}
    Addresses.remove {}
    Fields.remove {}

  setUpClient: ->
    @countsCollection ?= new Meteor.Collection 'Counts'

  @basic: (publishName) -> [
    ->
      @userId = Random.id()
      @countId = Random.id()

      @assertSubscribeSuccessful publishName, @userId, @expect()
      @assertSubscribeSuccessful 'users-posts-count', @userId, @countId, @expect()
  ,
    ->
      @assertEqual Posts.find().fetch(), []
      @assertEqual @countsCollection.findOne(@countId)?.count, 0

      @posts = []

      for i in [0...10]
        Posts.insert {}, @expect (error, id) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue id
          @posts.push id

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertEqual Posts.find().fetch(), []
      @assertEqual @countsCollection.findOne(@countId)?.count, 0

      Users.insert
        _id: @userId
        posts: @posts
      ,
        @expect (error, userId) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue userId
          @assertEqual userId, @userId

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts
      @assertEqual @countsCollection.findOne(@countId)?.count, @posts.length

      @shortPosts = @posts[0...5]

      Users.update @userId,
        posts: @shortPosts
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @shortPosts
      @assertEqual @countsCollection.findOne(@countId)?.count, @shortPosts.length

      Users.update @userId,
        posts: []
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), []
      @assertEqual @countsCollection.findOne(@countId)?.count, 0

      Users.update @userId,
        posts: @posts
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField, true
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts
      @assertEqual @countsCollection.findOne(@countId)?.count, @posts.length

      Posts.remove @posts[0], @expect (error, count) =>
        @assertFalse error, error?.toString?() or error
        @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts[1..]
      @assertEqual @countsCollection.findOne(@countId)?.count, @posts.length - 1

      Users.remove @userId,
        @expect (error) =>
          @assertFalse error, error?.toString?() or error

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), []
      @assertEqual @countsCollection.findOne(@countId)?.count, 0
  ]

  testClientBasic: @basic 'users-posts'

  testClientBasicForeach: @basic 'users-posts-foreach'

  testClientUnsubscribing: [
    ->
      @userId = Random.id()
      @countId = Random.id()

      @assertSubscribeSuccessful 'users-posts', @userId, @expect()
      @assertSubscribeSuccessful 'users-posts-count', @userId, @countId, @expect()
  ,
    ->
      @assertEqual Posts.find().fetch(), []
      @assertEqual @countsCollection.findOne(@countId)?.count, 0

      @posts = []

      for i in [0...10]
        Posts.insert {}, @expect (error, id) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue id
          @posts.push id

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertEqual Posts.find().fetch(), []
      @assertEqual @countsCollection.findOne(@countId)?.count, 0

      Users.insert
        _id: @userId
        posts: @posts
      ,
        @expect (error, userId) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue userId
          @assertEqual userId, @userId

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts
      @assertEqual @countsCollection.findOne(@countId)?.count, @posts.length

      # We have to update posts to trigger at least one rerun.
      Users.update @userId,
        posts: _.shuffle @posts
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts
      @assertEqual @countsCollection.findOne(@countId)?.count, @posts.length

      callback = @expect()
      @postsSubscribe = Meteor.subscribe 'posts', @posts,
        onReady: callback
        onError: (error) =>
          @assertFail
            type: 'subscribe'
            message: "Subscrption to endpoint failed, but should have succeeded."
          callback()
      @unsubscribeAll()

      Meteor.setTimeout @expect(), 2000
  ,
    ->
      # After unsubscribing from the reactive publish which added dummyField,
      # dummyField should be removed from documents available on the client side
      Posts.find().forEach (post) =>
        @assertIsUndefined post.dummyField
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts

      @postsSubscribe.stop()
  ]

  testClientRemoveField: [
    ->
      @userId = Random.id()

      @assertSubscribeSuccessful 'users-posts', @userId, @expect()
  ,
    ->
      @assertEqual Posts.find().fetch(), []

      Fields.insert
        _id: @userId
        foo: 1
        dummyField: 1
      ,
        @expect (error, id) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue id
          @fieldsId = id

      Posts.insert {foo: 'bar'}, @expect (error, id) =>
        @assertFalse error, error?.toString?() or error
        @assertTrue id
        @postId = id

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertEqual Posts.find().fetch(), []

      Users.insert
        _id: @userId
        posts: [@postId]
      ,
        @expect (error, userId) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue userId
          @assertEqual userId, @userId

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual Posts.find().fetch(), [
        _id: @postId
        foo: 'bar'
        dummyField: true
      ]

      Posts.update @postId,
        $set:
          foo: 'baz'
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual Posts.find().fetch(), [
        _id: @postId
        foo: 'baz'
        dummyField: true
      ]

      Posts.update @postId,
        $unset:
          foo: ''
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual Posts.find().fetch(), [
        _id: @postId
        dummyField: true
      ]

      Posts.update @postId,
        $set:
          foo: 'bar'
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual Posts.find().fetch(), [
        _id: @postId
        foo: 'bar'
        dummyField: true
      ]

      Fields.update @userId,
        $unset:
          foo: ''
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual Posts.find().fetch(), [
        _id: @postId
        dummyField: true
      ]
  ]

  @multiple: (publishName) -> [
    ->
      @userId = Random.id()

      @assertSubscribeSuccessful publishName, @userId, @expect()
    ->
      @assertEqual Posts.find().fetch(), []
      @assertEqual Addresses.find().fetch(), []

      @posts = []

      for i in [0...10]
        Posts.insert {}, @expect (error, id) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue id
          @posts.push id

      @addresses = []

      for i in [0...10]
        Addresses.insert {}, @expect (error, id) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue id
          @addresses.push id

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertEqual Posts.find().fetch(), []
      @assertEqual Addresses.find().fetch(), []

      Users.insert
        _id: @userId
        posts: @posts
        addresses: @addresses
      ,
        @expect (error, userId) =>
          @assertFalse error, error?.toString?() or error
          @assertTrue userId
          @assertEqual userId, @userId

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts
      @assertItemsEqual _.pluck(Addresses.find().fetch(), '_id'), @addresses

      Users.update @userId,
        $set:
          posts: @posts[0..5]
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts[0..5]
      @assertItemsEqual _.pluck(Addresses.find().fetch(), '_id'), @addresses

      Users.update @userId,
        $set:
          addresses: @addresses[0..5]
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts[0..5]
      @assertItemsEqual _.pluck(Addresses.find().fetch(), '_id'), @addresses[0..5]

      Users.update @userId,
        $unset:
          addresses: ''
      ,
        @expect (error, count) =>
          @assertFalse error, error?.toString?() or error
          @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts[0..5]
      @assertItemsEqual _.pluck(Addresses.find().fetch(), '_id'), []

      Users.remove @userId, @expect (error, count) =>
        @assertFalse error, error?.toString?() or error
        @assertEqual count, 1

      Meteor.setTimeout @expect(), 200 # ms
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), []
      @assertItemsEqual _.pluck(Addresses.find().fetch(), '_id'), []
  ]

  testClientMultiple: @multiple 'users-posts-and-addresses'

  testClientMultipleTogether: @multiple 'users-posts-and-addresses-together'

  testClientReactiveTime: [
    ->
      @assertSubscribeSuccessful 'recent-posts', @expect()

      @changes = []

      @handle = Posts.find(
        timestamp:
          $exists: true
      ).observeChanges
        added: (id, fields) =>
          @changes.push {added: id, timestamp: new Date().valueOf()}
        changes: (id, fields) =>
          @assertFail()
        removed: (id) =>
          @changes.push {removed: id, timestamp: new Date().valueOf()}
    ->
      @assertEqual Posts.find(timestamp: $exists: true).fetch(), []

      @posts = []

      for i in [0...10]
        timestamp =  new Date().valueOf() + i * 91 # ms
        do (timestamp) =>
          # We use a method to not have any client-side simulation which can
          # interfere with the observation of the Posts collection.
          Meteor.call 'insertPost', timestamp, @expect (error, id) =>
            @assertFalse error, error?.toString?() or error
            @assertTrue id
            @posts.push
              _id: id
              timestamp: timestamp

      # We have to wait for all posts to be inserted and pushed to the client.
      Meteor.setTimeout @expect(), 300 # ms
    ->
      @posts = _.sortBy @posts, 'timestamp'

      @assertEqual Posts.find(
        timestamp:
          $exists: true
      ,
        sort:
          timestamp: 1
      ).fetch(), @posts

      # We wait for 2000 ms for all documents to be removed, and then a bit more
      # to make sure the publish endpoint gets synced to the client.
      Meteor.setTimeout @expect(), 3000 # ms
    ->
      @assertEqual Posts.find(
        timestamp:
          $exists: true
      ).fetch(), []

      @assertEqual @changes.length, 20

      # There should be first changes for adding, and then in the same order changes for removing.
      postsId = _.pluck @posts, '_id'
      @assertEqual _.map(@changes, (change) -> change.added or change.removed), postsId.concat postsId

      addedTimestamps = (change.timestamp for change in @changes when change.added)
      removedTimestamps = (change.timestamp for change in @changes when change.removed)

      addedTimestamps.sort()
      removedTimestamps.sort()

      sum = (list) -> _.reduce list, ((memo, num) -> memo + num), 0

      averageAdded = sum(addedTimestamps) / addedTimestamps.length
      averageRemoved = sum(removedTimestamps) / removedTimestamps.length

      # Removing starts after 2000 ms, so there should be at least this difference between averages.
      @assertTrue averageAdded + 2000 < averageRemoved

      removedDelta = 0

      for removed, i in removedTimestamps when i < removedTimestamps.length - 1
        removedDelta += removedTimestamps[i + 1] - removed

      removedDelta /= removedTimestamps.length - 1

      # Each removed is approximately 91 ms apart. So the average of deltas should be somewhere there.
      @assertTrue removedDelta > 80
  ]

# Register the test case.
ClassyTestCase.addTest new ReactivePublishTestCase()
