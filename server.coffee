Fiber = Npm.require 'fibers'

checkNames = (publish, collectionNames, computation, result) ->
  if result and _.isArray result
    resultNames = (cursor._getCollectionName() for cursor in result when '_getCollectionName' of cursor)
  else if result and _.isObject result and '_getCollectionName' of result
    resultNames = [result._getCollectionName()]
  else
    resultNames = []

  collectionNames[computation._id] = resultNames if computation

  for computationId, names of collectionNames when not computation or computationId isnt "#{computation._id}"
    for collectionName in names when collectionName in resultNames
      publish.error new Error "Multiple cursors for collection '#{collectionName}'"
      return false

  true

wrapCallbacks = (callbacks, initializingReference) ->
  # If observeChanges is called inside a reactive context we have to make extra effort to pass the computation to the
  # observeChanges callbacks so that the computation is available to the "added" publish method, if it is called. We use
  # fiber object for that. observeChanges callbacks are not called in a reactive context. Additionally, we want this to
  # be passed only during the observeChanges initialization (when it is calling "added" callbacks in a blocking manner).
  if Tracker.active
    Meteor._nodeCodeMustBeInFiber()
    currentComputation = Tracker.currentComputation
    callbacks = _.clone callbacks
    for callbackName, callback of callbacks when callbackName in ['added', 'changed', 'removed', 'addedBefore', 'movedBefore']
      do (callbackName, callback) ->
        callbacks[callbackName] = (args...) ->
          if initializingReference.initializing
            previousPublishComputation = Fiber.current._publishComputation
            Fiber.current._publishComputation = currentComputation
            try
              callback.apply null, args
            finally
              Fiber.current._publishComputation = previousPublishComputation
          else
            callback.apply null, args

  callbacks

originalObserveChanges = MongoInternals.Connection::_observeChanges
MongoInternals.Connection::_observeChanges = (cursorDescription, ordered, callbacks) ->
  initializing = true

  callbacks = wrapCallbacks callbacks, initializing: initializing

  handle = originalObserveChanges.call @, cursorDescription, ordered, callbacks
  initializing = false
  handle

originalLocalCollectionCursorObserveChanges = LocalCollection.Cursor::observeChanges
LocalCollection.Cursor::observeChanges = (options) ->
  initializing = true

  options = wrapCallbacks options, initializing: initializing

  handle = originalLocalCollectionCursorObserveChanges.call @, options
  initializing = false
  handle

extendPublish (name, publishFunction, options) ->
  newPublishFunction = (args...) ->
    publish = @

    oldDocuments = {}
    documents = {}

    collectionNames = {}

    publish._currentComputation = ->
      if Tracker.active
        return Tracker.currentComputation
      else
        # Computation can also be passed through current fiber in the case the "added" method is called
        # from the observeChanges callback from an observeChanges called inside a reactive context.
        return Fiber.current._publishComputation

      null

    publish._installCallbacks = ->
      computation = @_currentComputation()

      return unless computation

      unless computation._publishOnStopSet
        computation._publishOnStopSet = true

        computation.onStop =>
          delete oldDocuments[computation._id]
          delete documents[computation._id]

      unless computation._publishAfterRunSet
        computation._publishAfterRunSet = true

        computation.afterRun =>
          # We remove those which are not published anymore.
          for collectionName of @_documents
            currentlyPublishedDocumentIds = _.keys(@_documents[collectionName] or {})
            currentComputationAddedDocumentIds = _.keys(documents[computation._id]?[collectionName] or {})
            # If afterRun for other autoruns in the publish function have not yet run, we have to look in "documents" as well.
            otherComputationsAddedDocumentsIds = _.union (_.keys(docs[collectionName] or {}) for computationId, docs of documents when computationId isnt "#{computation._id}")...
            # But after afterRun, "documents" is empty to be ready for next rerun of the computation, so we look into "oldDocuments".
            otherComputationsPreviouslyAddedDocumentsIds = _.union (_.keys(docs[collectionName] or {}) for computationId, docs of oldDocuments when computationId isnt "#{computation._id}")...

            # We ignore IDs found in both otherComputationsAddedDocumentsIds and otherComputationsPreviouslyAddedDocumentsIds
            # which might ignore more IDs then necessary (an ID might be previously added which has not been added in this
            # iteration) but this is OK because in afterRun of other computations this will be corrected and documents
            # with those IDs removed.
            for id in _.difference currentlyPublishedDocumentIds, currentComputationAddedDocumentIds, otherComputationsAddedDocumentsIds, otherComputationsPreviouslyAddedDocumentsIds
              @removed collectionName, @_idFilter.idParse id

          computation.beforeRun =>
            oldDocuments[computation._id] = documents[computation._id] or {}
            documents[computation._id] = {}

          computation._publishAfterRunSet = false

        computation._trackerInstance.requireFlush()

      return

    originalAdded = publish.added
    publish.added = (collectionName, id, fields) ->
      stringId = @_idFilter.idStringify id

      @_installCallbacks()

      currentComputation = @_currentComputation()
      Meteor._ensure(documents, currentComputation._id, collectionName)[stringId] = true if currentComputation

      # If document as already present in publish then we call changed to send updated fields (Meteor sends only a diff).
      # This can hide some errors in publish functions if they one calls "added" on an existing document and we could
      # make it so that this behavior works only inside reactive computation (if "currentComputation" is set), but we
      # can also make it so that publish function tries to do something smarter (sending a diff) in all cases, as we do.
      if @_documents[collectionName]?[stringId]
        oldFields = {}
        # If some field existed before, but does not exist anymore, we have to remove it by calling "changed"
        # with value set to "undefined". So we look into current session's state and see which fields are currently
        # known and create an object of same fields, just all values set to "undefined". We then override some fields
        # with new values. Only top-level fields matter.
        for field of @_session.getCollectionView(collectionName)?.documents?[stringId]?.dataByKey or {}
          oldFields[field] = undefined
        @changed collectionName, id, _.extend oldFields, fields
      else
        originalAdded.call @, collectionName, id, fields

    ready = false

    originalReady = publish.ready
    publish.ready = ->
      @_installCallbacks()

      # Mark it as ready only the first time.
      originalReady.call @ unless ready
      ready = true

      # To return nothing.
      return

    handles = []
    # This autorun is nothing special, just that it makes sure handles are stopped when publish stops,
    # and that you can return cursors from the function which would be automatically published.
    publish.autorun = (runFunc) ->
      handle = Tracker.autorun (computation) ->
        result = runFunc.call publish, computation

        unless checkNames publish, collectionNames, computation, result
          computation.stop()
          return

        # Specially handle if computation has been returned.
        if result instanceof Tracker.Computation
          if publish._isDeactivated()
            result.stop()
          else
            handles.push result
        else
          publish._publishHandlerResult result unless publish._isDeactivated()

      handles.push handle
      handle

    publish.onStop ->
      while handles.length
        handle = handles.shift()
        handle?.stop()

    result = publishFunction.apply publish, args

    return unless checkNames publish, collectionNames, null, result

    # Specially handle if computation has been returned.
    if result instanceof Tracker.Computation
      handles.push result
      # Do not return anything.
      return

    else
      result

  [name, newPublishFunction, options]
