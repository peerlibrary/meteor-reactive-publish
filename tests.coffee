Users = new Meteor.Collection 'Users_meteor_reactive_publish_tests'
Posts = new Meteor.Collection 'Posts_meteor_reactive_publish_tests'

intersectionObjects = (array, rest...) ->
  _.filter _.uniq(array), (item) ->
    _.every rest, (other) ->
      _.any other, (element) -> _.isEqual element, item

testSetEqual = (test, a, b) ->
  a ||= []
  b ||= []

  if a.length is b.length and intersectionObjects(a, b).length is a.length
    test.ok()
  else
    test.fail
      type: 'assert_set_equal'
      actual: JSON.stringify a
      expected: JSON.stringify b

if Meteor.isServer
  # Initialize the database
  Users.remove {}
  Posts.remove {}

  Meteor.publish null, ->
    Users.find()

  Meteor.publish 'posts', (ids) ->
    Posts.find
      _id:
        $in: ids

  Meteor.publish 'users-posts', (userId) ->
    user = Users.findOne userId,
      fields:
        posts: 1

    Posts.find(
      _id:
        $in: user?.posts or []
    ).observeChanges
      added: (id, fields) =>
        fields.dummyField = true
        @added 'Posts_meteor_reactive_publish_tests', id, fields
      changed: (id, fields) =>
        @changed 'Posts_meteor_reactive_publish_tests', id, fields
      removed: (id) =>
        @removed 'Posts_meteor_reactive_publish_tests', id

    @ready()

  Meteor.publish 'users-posts-count', (userId, countId) ->
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
        count++
        @changed 'Counts', countId, count: count unless initializing
      removed: (id) =>
        count--
        @changed 'Counts', countId, count: count unless initializing

    initializing = false

    @added 'Counts', countId,
      count: count

    @ready()

if Meteor.isClient
  Counts = new Meteor.Collection 'Counts'

  testAsyncMulti 'reactive-publish - basic', [
    (test, expect) ->
      @userId = Random.id()
      @countId = Random.id()

      @usersPostsSubscribe = Meteor.subscribe 'users-posts', @userId,
        onReady: expect()
        onError: (error) ->
          test.exception error
      @usersPostsCount = Meteor.subscribe 'users-posts-count', @userId, @countId,
        onReady: expect()
        onError: (error) ->
          test.exception error
  ,
    (test, expect) ->
      test.equal Posts.find().fetch(), []
      test.equal Counts.findOne(@countId)?.count, 0

      @posts = []

      for i in [0...10]
        Posts.insert {}, expect (error, id) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue id
          @posts.push id
  ,
    (test, expect) ->
      test.equal Posts.find().fetch(), []
      test.equal Counts.findOne(@countId)?.count, 0

      Users.insert
        _id: @userId
        posts: @posts
      ,
        expect (error, userId) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue userId
          test.equal userId, @userId
  ,
    (test, expect) ->
      Posts.find().forEach (post) ->
        test.isTrue post.dummyField, true
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), @posts
      test.equal Counts.findOne(@countId)?.count, @posts.length

      @shortPosts = @posts[0...5]

      Users.update @userId,
        posts: @shortPosts
      ,
        expect (error, count) =>
          test.isFalse error, error?.toString?() or error
          test.equal count, 1
  ,
    (test, expect) ->
      Posts.find().forEach (post) ->
        test.isTrue post.dummyField, true
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), @shortPosts
      test.equal Counts.findOne(@countId)?.count, @shortPosts.length

      Users.update @userId,
        posts: []
      ,
        expect (error, count) =>
          test.isFalse error, error?.toString?() or error
          test.equal count, 1
  ,
    (test, expect) ->
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), []
      test.equal Counts.findOne(@countId)?.count, 0

      Users.update @userId,
        posts: @posts
      ,
        expect (error, count) =>
          test.isFalse error, error?.toString?() or error
          test.equal count, 1
  ,
    (test, expect) ->
      Posts.find().forEach (post) ->
        test.isTrue post.dummyField, true
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), @posts
      test.equal Counts.findOne(@countId)?.count, @posts.length

      Posts.remove @posts[0], expect (error, count) =>
          test.isFalse error, error?.toString?() or error
          test.equal count, 1
  ,
    (test, expect) ->
      Posts.find().forEach (post) ->
        test.isTrue post.dummyField, true
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), @posts[1..]
      test.equal Counts.findOne(@countId)?.count, @posts.length - 1

      Users.remove @userId,
        expect (error) =>
          test.isFalse error, error?.toString?() or error
  ,
    (test, expect) ->
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), []
      test.equal Counts.findOne(@countId)?.count, 0

      @usersPostsSubscribe.stop()
      @usersPostsCount.stop()
  ]

  testAsyncMulti 'reactive-publish - unsubscribing', [
    (test, expect) ->
      @userId = Random.id()
      @countId = Random.id()

      @usersPostsSubscribe = Meteor.subscribe 'users-posts', @userId,
        onReady: expect()
        onError: (error) ->
          test.exception error
      @usersPostsCount = Meteor.subscribe 'users-posts-count', @userId, @countId,
        onReady: expect()
        onError: (error) ->
          test.exception error
  ,
    (test, expect) ->
      test.equal Posts.find().fetch(), []
      test.equal Counts.findOne(@countId)?.count, 0

      @posts = []

      for i in [0...10]
        Posts.insert {}, expect (error, id) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue id
          @posts.push id
  ,
    (test, expect) ->
      test.equal Posts.find().fetch(), []
      test.equal Counts.findOne(@countId)?.count, 0

      Users.insert
        _id: @userId
        posts: @posts
      ,
        expect (error, userId) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue userId
          test.equal userId, @userId
  ,
    (test, expect) ->
      Posts.find().forEach (post) ->
        test.isTrue post.dummyField, true
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), @posts
      test.equal Counts.findOne(@countId)?.count, @posts.length

      # We have to update posts to trigger at least one rerun
      Users.update @userId,
        posts: _.shuffle @posts
      ,
        expect (error, count) =>
          test.isFalse error, error?.toString?() or error
          test.equal count, 1
  ,
    (test, expect) ->
      Posts.find().forEach (post) ->
        test.isTrue post.dummyField, true
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), @posts
      test.equal Counts.findOne(@countId)?.count, @posts.length

      Meteor.subscribe 'posts', @posts,
        onReady: expect()
        onError: (error) ->
          test.exception error
      @usersPostsSubscribe.stop()

      # Let's wait a but for subscription to really stop
      Meteor.setTimeout expect(), 1000
  ,
    (test, expect) ->
      # After unsubscribing from the reactive publish which added dummyField,
      # dummyField should be removed from documents available on the client side
      Posts.find().forEach (post) ->
        test.isUndefined post.dummyField
      testSetEqual test, _.pluck(Posts.find().fetch(), '_id'), @posts

      @usersPostsSubscribe.stop()
      @usersPostsCount.stop()
  ]
