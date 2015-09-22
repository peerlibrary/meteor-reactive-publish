Fiber = Npm.require 'fibers'

originalPublish = Meteor.publish

originalObserveChanges = MongoInternals.Connection::_observeChanges
MongoInternals.Connection::_observeChanges = (cursorDescription, ordered, callbacks) ->
  initializing = true

  if Tracker.active
    Meteor._nodeCodeMustBeInFiber()
    currentComputation = Tracker.currentComputation
    callbacks = _.clone callbacks
    for callbackName, callback of callbacks
      do (callbackName, callback) ->
        callbacks[callbackName] = (args...) ->
          if initializing
            previousPublishComputation = Fiber.current._publishComputation
            Fiber.current._publishComputation = currentComputation
            try
              callback.apply null, args
            finally
              Fiber.current._publishComputation = previousPublishComputation
          else
            callback.apply null, args

  handle = originalObserveChanges.call @, cursorDescription, ordered, callbacks
  initializing = false
  handle

Meteor.publish = (name, publishFunction) ->
  originalPublish name, (args...) ->
    publish = @

    oldDocuments = {}
    documents = {}

    publish._setAfterFlush = (computation) ->
      unless computation._publishAfterFlushSet
        computation._publishAfterFlushSet = true

        computation._trackerInstance.afterFlushCallbacks.push =>
          # We remove those which are not published anymore.
          for collectionName of @_documents
            currentlyPublishedDocumentIds = _.keys(@_documents[collectionName] or {})
            currentComputationAddedDocumentIds = _.keys(documents[computation._id]?[collectionName] or {})
            # If afterFlush for other autoruns in the publish function have not yet run, we have to look in "documents" as well.
            otherComputationsAddedDocumentsIds = _.union (_.keys(docs[collectionName] or {}) for computationId, docs of documents when computationId isnt "#{computation._id}")...
            # But after afterFlush, "documents" is empty to be ready for next rerun of the computation, so we look into "oldDocuments".
            otherComputationsPreviouslyAddedDocumentsIds = _.union (_.keys(docs[collectionName] or {}) for computationId, docs of oldDocuments when computationId isnt "#{computation._id}")...

            # We ignore IDs found in both otherComputationsAddedDocumentsIds and otherComputationsPreviouslyAddedDocumentsIds
            # which might ignore more IDs then necessary (an ID might be previously added which has not been added in this
            # iteration) but this is OK because in afterFlush of other computations this will be corrected and documents
            # with those IDs removed.
            for id in _.difference currentlyPublishedDocumentIds, currentComputationAddedDocumentIds, otherComputationsAddedDocumentsIds, otherComputationsPreviouslyAddedDocumentsIds
              @removed collectionName, id

          oldDocuments[computation._id] = documents[computation._id] or {}
          documents[computation._id] = {}
          computation._publishAfterFlushSet = false

        computation._trackerInstance.requireFlush()

    originalAdded = publish.added
    publish.added = (collectionName, id, fields) ->
      stringId = @_idFilter.idStringify id

      if Tracker.active
        currentComputation = Tracker.currentComputation
      else
        currentComputation = Fiber.current._publishComputation
      if currentComputation
        @_setAfterFlush currentComputation
        Meteor._ensure(documents, currentComputation._id, collectionName)[stringId] = true
      # If document as already present in publish then we call changed to send updated fields (Meteor sends only a diff).
      if @_documents[collectionName]?[stringId]
        oldFields = {}
        # If some field existed before, but does not exist anymore, we have to remove it by calling "changed"
        # with value set to "undefined". So we look into current session's state and see which fields are currently
        # known and create an object of same fields, just all values set to "undefined". We then override some fields
        # with new values. Only top-level fields matter.
        for field of @_session.getCollectionView(collectionName)?.documents?[id]?.dataByKey or {}
          oldFields[field] = undefined
        @changed collectionName, id, _.extend oldFields, fields
      else
        originalAdded.call @, collectionName, id, fields

    ready = false

    originalReady = publish.ready
    publish.ready = ->
      if Tracker.active
        currentComputation = Tracker.currentComputation
      else
        currentComputation = Fiber.current._publishComputation
      if currentComputation
        @_setAfterFlush currentComputation

      # Mark it as ready only the first time
      originalReady.call @ unless ready
      ready = true
      # To return nothing.
      return

    handles = []
    publish.autorun = (runFunc) ->
      handle = Tracker.autorun (computation) ->
        result = runFunc computation

        publishHandlerResult publish, result unless publish._isDeactivated()

      handles.push handle
      handle

    publish.onStop ->
      while handle = handles.pop()
        handle.stop()

    publishFunction.apply publish, args
