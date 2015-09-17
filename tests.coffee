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
        fields.dummyField = true
        @added 'Posts_meteor_reactive_publish_tests', id, fields
      changed: (id, fields) =>
        @changed 'Posts_meteor_reactive_publish_tests', id, fields
      removed: (id) =>
        @removed 'Posts_meteor_reactive_publish_tests', id

    @ready()

  Meteor.publish 'users-posts-and-addresses', (userId) ->
    user1 = Users.findOne userId,
      fields:
        posts: 1

    user2 = Users.findOne userId,
      fields:
        addresses: 1

    # TODO: Split.
    [
      Posts.find(
        _id:
          $in: user1?.posts or []
      )
    ,
      Addresses.find(
        _id:
          $in: user2?.addresses or []
      )
    ]

  Meteor.publish 'users-posts-and-addresses-together', (userId) ->
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

  testClientBasic: [
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
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField, true
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts
      @assertEqual @countsCollection.findOne(@countId)?.count, @posts.length

      Posts.remove @posts[0], @expect (error, count) =>
        @assertFalse error, error?.toString?() or error
        @assertEqual count, 1
  ,
    ->
      Posts.find().forEach (post) =>
        @assertTrue post.dummyField
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts[1..]
      @assertEqual @countsCollection.findOne(@countId)?.count, @posts.length - 1

      Users.remove @userId,
        @expect (error) =>
          @assertFalse error, error?.toString?() or error
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), []
      @assertEqual @countsCollection.findOne(@countId)?.count, 0
  ]

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

      # Let's wait a but for subscription to really stop
      Meteor.setTimeout @expect(), 1000
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
  ,
    ->
      @assertItemsEqual Posts.find().fetch(), [
        _id: @postId
        dummyField: true
      ]
  ]

  @multiple: [
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
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), @posts[0..5]
      @assertItemsEqual _.pluck(Addresses.find().fetch(), '_id'), []

      Users.remove @userId, @expect (error, count) =>
        @assertFalse error, error?.toString?() or error
        @assertEqual count, 1
  ,
    ->
      @assertItemsEqual _.pluck(Posts.find().fetch(), '_id'), []
      @assertItemsEqual _.pluck(Addresses.find().fetch(), '_id'), []
  ]

  testClientMultiple: [
    ->
      @userId = Random.id()

      @assertSubscribeSuccessful 'users-posts-and-addresses', @userId, @expect()
  ].concat @multiple

  testClientMultipleTogether: [
    ->
      @userId = Random.id()

      @assertSubscribeSuccessful 'users-posts-and-addresses-together', @userId, @expect()
  ].concat @multiple

# Register the test case.
ClassyTestCase.addTest new ReactivePublishTestCase()
