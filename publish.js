// Copy of code from Subscription.prototype._runHandler from ddp-server/livedata_server.js.
// See https://github.com/meteor/meteor/pull/5212

publishHandlerResult = function (self, res) {
  // SPECIAL CASE: Instead of writing their own callbacks that invoke
  // this.added/changed/ready/etc, the user can just return a collection
  // cursor or array of cursors from the publish function; we call their
  // _publishCursor method which starts observing the cursor and publishes the
  // results. Note that _publishCursor does NOT call ready().
  //
  // XXX This uses an undocumented interface which only the Mongo cursor
  // interface publishes. Should we make this interface public and encourage
  // users to implement it themselves? Arguably, it's unnecessary; users can
  // already write their own functions like
  //   var publishMyReactiveThingy = function (name, handler) {
  //     Meteor.publish(name, function () {
  //       var reactiveThingy = handler();
  //       reactiveThingy.publishMe();
  //     });
  //   };
  var isCursor = function (c) {
    return c && c._publishCursor;
  };
  if (isCursor(res)) {
    try {
      res._publishCursor(self);
    } catch (e) {
      self.error(e);
      return;
    }
    // _publishCursor only returns after the initial added callbacks have run.
    // mark subscription as ready.
    self.ready();
  } else if (_.isArray(res)) {
    // check all the elements are cursors
    if (! _.all(res, isCursor)) {
      self.error(new Error("Publish function returned an array of non-Cursors"));
      return;
    }
    // find duplicate collection names
    // XXX we should support overlapping cursors, but that would require the
    // merge box to allow overlap within a subscription
    var collectionNames = {};
    for (var i = 0; i < res.length; ++i) {
      var collectionName = res[i]._getCollectionName();
      if (_.has(collectionNames, collectionName)) {
        self.error(new Error(
          "Publish function returned multiple cursors for collection " +
            collectionName));
        return;
      }
      collectionNames[collectionName] = true;
    };

    try {
      _.each(res, function (cur) {
        cur._publishCursor(self);
      });
    } catch (e) {
      self.error(e);
      return;
    }
    self.ready();
  } else if (res) {
    // truthy values other than cursors or arrays are probably a
    // user mistake (possible returning a Mongo document via, say,
    // `coll.findOne()`).
    self.error(new Error("Publish function can only return a Cursor or "
                         + "an array of Cursors"));
  }
};
