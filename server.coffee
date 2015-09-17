originalPublish = Meteor.publish

Meteor.publish = (name, publishFunction) ->
  originalPublish name, (args...) ->
    publish = @

    relatedPublish = null
    ready = false

    publishDocuments = ->
      oldRelatedPublish = relatedPublish

      Tracker.nonreactive =>
        relatedPublish = publish._recreate()

        # We copy overridden methods if they exist
        for own key, value of publish when key in ['added', 'changed', 'removed', 'ready', 'stop', 'error']
          relatedPublish[key] = value

        # If there are any extra fields which do not exist in recreated related publish
        # (because they were added by some other code), copy them over
        # TODO: This copies also @related, test how recursive @related works
        for own key, value of publish when key not of relatedPublish
          relatedPublish[key] = value

        relatedPublishAdded = relatedPublish.added
        relatedPublish.added = (collectionName, id, fields) ->
          stringId = @_idFilter.idStringify id
          # If document as already present in oldRelatedPublish then we just set
          # relatedPublish's _documents and call changed to send updated fields
          # (Meteor sends only a diff).
          if oldRelatedPublish?._documents[collectionName]?[stringId]
            Meteor._ensure(@_documents, collectionName)[stringId] = true
            oldFields = {}
            # If some field existed before, but does not exist anymore, we have to remove it by calling "changed"
            # with value set to "undefined". So we look into current session's state and see which fields are currently
            # known and create an object of same fields, just all values set to "undefined". We then override some fields
            # with new values. Only top-level fields matter.
            for field of @_session.getCollectionView(collectionName)?.documents?[id]?.dataByKey or {}
              oldFields[field] = undefined
            @changed collectionName, id, _.extend oldFields, fields
          else
            relatedPublishAdded.call @, collectionName, id, fields

        relatedPublish.ready = ->
          # Mark it as ready only the first time
          publish.ready() unless ready
          ready = true
          # To return nothing.
          return

        relatedPublish.stop = (relatedChange) ->
          if relatedChange
            # We only deactivate (which calls stop callbacks as well) because we
            # have manually removed only documents which are not published again.
            @_deactivate()
          else
            # We do manually what would _stopSubscription do, but without
            # subscription handling. This should be done by the parent publish.
            @_removeAllDocuments()
            @_deactivate()
            publish.stop()
          # To return nothing.
          return

      relatedPublish._handler = publishFunction
      relatedPublish._runHandler()

      return unless oldRelatedPublish

      Tracker.nonreactive =>
        # We remove those which are not published anymore
        for collectionName in _.keys(oldRelatedPublish._documents)
          for id in _.difference _.keys(oldRelatedPublish._documents[collectionName] or {}), _.keys(relatedPublish._documents[collectionName] or {})
            oldRelatedPublish.removed collectionName, id

        oldRelatedPublish.stop true
        oldRelatedPublish = null

    handle = Tracker.autorun (computation) =>
      publishDocuments()

    publish.onStop ->
      handle?.stop()
      handle = null
      relatedPublish?.stop()
      relatedPublish = null

    # To return nothing.
    return
