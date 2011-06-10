(function() {
  /*
  Redis-Tagging
  A tagging helper library for NodeJS and Redis
  Version 0.2
  Copyright (c) 2011 TCS    dev (at) tcs.de
  Released under the MIT License
  */  var RedisTagging, RedisTaggingSingleNS;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; }, __hasProp = Object.prototype.hasOwnProperty, __extends = function(child, parent) {
    for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; }
    function ctor() { this.constructor = child; }
    ctor.prototype = parent.prototype;
    child.prototype = new ctor;
    child.__super__ = parent.prototype;
    return child;
  };
  RedisTagging = (function() {
    function RedisTagging(redis, nsprefix) {
      this.redis = redis;
      this.nsprefix = nsprefix;
      this.toptags = __bind(this.toptags, this);;
      this.tags = __bind(this.tags, this);;
      this.allids = __bind(this.allids, this);;
      this.get = __bind(this.get, this);;
      this.remove = __bind(this.remove, this);;
      this.set = __bind(this.set, this);;
      this._deleteID = __bind(this._deleteID, this);;
    }
    RedisTagging.prototype._deleteID = function(ns, id, callback) {
      var id_index, mc;
      mc = [];
      id_index = ns + ':ID:' + id;
      this.redis.smembers(id_index, __bind(function(err, resp) {
        var tag, _i, _len;
        if (resp.length) {
          for (_i = 0, _len = resp.length; _i < _len; _i++) {
            tag = resp[_i];
            mc.push(['zincrby', ns + ':TAGCOUNT', -1, tag]);
            mc.push(['zrem', ns + ':TAGS:' + tag, id]);
          }
          mc.push(['del', id_index]);
          mc.push(['zremrangebyscore', ns + ':TAGCOUNT', 0, 0]);
        }
        callback(mc);
      }, this));
    };
    RedisTagging.prototype.set = function(namespace, id, score, tags, callback) {
      var id_index, ns;
      ns = this.nsprefix + namespace;
      id_index = ns + ':ID:' + id;
      this._deleteID(ns, id, __bind(function(mc) {
        var tag, _i, _len;
        for (_i = 0, _len = tags.length; _i < _len; _i++) {
          tag = tags[_i];
          mc.push(['zincrby', ns + ':TAGCOUNT', 1, tag]);
          mc.push(['sadd', id_index, tag]);
          mc.push(['zadd', ns + ':TAGS:' + tag, score, id]);
        }
        this.redis.multi(mc).exec(function(err, resp) {
          callback({
            ok: true
          });
        });
      }, this));
    };
    RedisTagging.prototype.remove = function(namespace, id, callback) {
      var ns;
      ns = this.nsprefix + namespace;
      this._deleteID(ns, id, __bind(function(mc) {
        if (mc.length) {
          this.redis.multi(mc).exec(function(err, resp) {
            callback({
              ok: true
            });
          });
        } else {
          callback({
            ok: true
          });
        }
      }, this));
    };
    RedisTagging.prototype.get = function(namespace, id, callback) {
      var ns;
      ns = this.nsprefix + namespace;
      this.redis.smembers(ns + ':ID:' + id, function(req, resp) {
        var tag, tags;
        tags = (function() {
          var _i, _len, _results;
          _results = [];
          for (_i = 0, _len = resp.length; _i < _len; _i++) {
            tag = resp[_i];
            _results.push(tag);
          }
          return _results;
        })();
        callback(tags);
      });
    };
    RedisTagging.prototype.allids = function(namespace, callback) {
      var prefix;
      prefix = this.nsprefix + namespace + ':ID:';
      this.redis.keys(prefix + '*', function(err, resp) {
        var e, o, rows, _prefix_len;
        _prefix_len = prefix.length;
        rows = (function() {
          var _i, _len, _results;
          _results = [];
          for (_i = 0, _len = resp.length; _i < _len; _i++) {
            e = resp[_i];
            _results.push(e.substr(_prefix_len));
          }
          return _results;
        })();
        o = {
          total_rows: rows.length,
          rows: rows
        };
        callback(o);
      });
    };
    RedisTagging.prototype.tags = function(namespace, p) {
      var lastelement, mc, ns, prefix, resultkey, rndkey, tag, tagsresult, _keys;
      ns = this.nsprefix + namespace;
      p = {
        tags: p.tags,
        limit: Number(p.limit || 100),
        offset: Number(p.offset || 0),
        withscores: Number(p.withscores) || 0,
        order: p.order === "asc" ? "" : "rev",
        type: (p.type || "inter").toLowerCase(),
        callback: p.callback
      };
      prefix = ns + ':TAGS:';
      lastelement = p.offset + p.limit - 1;
      mc = [];
      if (p.tags.length > 1) {
        rndkey = ns + (new Date().getTime()) + '_' + Math.floor(Math.random() * 9999999999);
        _keys = (function() {
          var _i, _len, _ref, _results;
          _ref = p.tags;
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            tag = _ref[_i];
            _results.push(prefix + tag);
          }
          return _results;
        })();
        mc.push(['z' + p.type + 'store', rndkey, _keys.length].concat(_keys).concat(['AGGREGATE', 'MIN']));
        if (p.limit > 0) {
          resultkey = rndkey;
        }
      } else if (p.tags.length === 1) {
        mc.push(['zcard', prefix + p.tags[0]]);
        if (p.limit > 0) {
          resultkey = prefix + p.tags[0];
        }
      }
      if (mc.length) {
        if (p.limit > 0) {
          tagsresult = ['z' + p.order + 'range', resultkey, p.offset, lastelement];
          if (p.withscores) {
            tagsresult = tagsresult.concat(['WITHSCORES']);
          }
          mc.push(tagsresult);
        }
        if (p.tags.length > 1) {
          mc.push(['del', rndkey]);
        }
        this.redis.multi(mc).exec(function(err, resp) {
          var e, i, rows;
          if (p.limit === 0) {
            rows = [];
          } else {
            rows = resp[1];
          }
          if (rows.length && p.withscores) {
            rows = (function() {
              var _len, _results;
              _results = [];
              for (i = 0, _len = rows.length; i < _len; i += 2) {
                e = rows[i];
                _results.push({
                  id: e,
                  score: rows[i + 1]
                });
              }
              return _results;
            })();
          }
          p.callback({
            total_rows: resp[0],
            rows: rows,
            limit: p.limit,
            offset: p.offset
          });
        });
      } else {
        p.callback({
          "error": "Supply at least one tag"
        });
      }
    };
    RedisTagging.prototype.toptags = function(namespace, amount, callback) {
      var ns, rediskey;
      ns = this.nsprefix + namespace;
      amount = Math.abs(amount) - 1;
      rediskey = ns + ':TAGCOUNT';
      this.redis.zcard(rediskey, __bind(function(err, resp) {
        var total_rows;
        total_rows = resp;
        this.redis.zrevrange(rediskey, 0, amount, 'WITHSCORES', function(err, resp) {
          var e, i, o, rows;
          rows = (function() {
            var _len, _results;
            _results = [];
            for (i = 0, _len = resp.length; i < _len; i += 2) {
              e = resp[i];
              _results.push({
                tag: e,
                count: Number(resp[i + 1])
              });
            }
            return _results;
          })();
          o = {
            total_rows: total_rows,
            rows: rows
          };
          callback(o);
        });
      }, this));
    };
    return RedisTagging;
  })();
  RedisTaggingSingleNS = (function() {
    function RedisTaggingSingleNS(redis, nsprefix, namespace) {
      this.redis = redis;
      this.nsprefix = nsprefix;
      this.namespace = namespace;
      this.toptags = __bind(this.toptags, this);;
      this.tags = __bind(this.tags, this);;
      this.allids = __bind(this.allids, this);;
      this.remove = __bind(this.remove, this);;
      this.get = __bind(this.get, this);;
      this.set = __bind(this.set, this);;
    }
    __extends(RedisTaggingSingleNS, RedisTagging);
    RedisTaggingSingleNS.prototype.set = function(id, score, tags, callback) {
      RedisTaggingSingleNS.__super__.set.call(this, this.namespace, id, score, tags, callback);
    };
    RedisTaggingSingleNS.prototype.get = function(id, callback) {
      RedisTaggingSingleNS.__super__.get.call(this, this.namespace, id, callback);
    };
    RedisTaggingSingleNS.prototype.remove = function(id, callback) {
      RedisTaggingSingleNS.__super__.remove.call(this, this.namespace, id, callback);
    };
    RedisTaggingSingleNS.prototype.allids = function(callback) {
      RedisTaggingSingleNS.__super__.allids.call(this, this.namespace, callback);
    };
    RedisTaggingSingleNS.prototype.tags = function(p) {
      RedisTaggingSingleNS.__super__.tags.call(this, this.namespace, p);
    };
    RedisTaggingSingleNS.prototype.toptags = function(amount) {
      RedisTaggingSingleNS.__super__.toptags.call(this, this.namespace, amount);
    };
    return RedisTaggingSingleNS;
  })();
  exports.multi_namespace = RedisTagging;
  exports.single_namespace = RedisTaggingSingleNS;
}).call(this);
