(function() {
  var DEFAULT_ROUTE, NAMESPACE_PREFIX, PORT, RedisTagging, connect, qs, redis, redis_tagger, redisclient, rt, url;
  PORT = 8010;
  DEFAULT_ROUTE = "/tagger";
  NAMESPACE_PREFIX = "tgs:";
  connect = require("connect");
  url = require("url");
  qs = require("querystring");
  redisclient = require("redis");
  redis = redisclient.createClient();
  RedisTagging = require("./redis-tagging").multi_namespace;
  rt = new RedisTagging(redis, NAMESPACE_PREFIX);
  redis_tagger = function(app) {
    var _replyJSON;
    _replyJSON = function(req, res, reply) {
      var u;
      u = qs.parse(url.parse(req.url).query);
      if (u.callback) {
        res.writeHead(200, {
          "Content-Type": "application/javascript; charset=UTF-8"
        });
        res.end(u.callback + '(' + JSON.stringify(reply) + ');');
      } else {
        res.writeHead(200, {
          "Content-Type": "application/json; charset=UTF-8"
        });
        res.end(JSON.stringify(reply));
      }
    };
    app.post(DEFAULT_ROUTE + "/id/:namespace/:id", function(req, res) {
      rt.set(req.params.namespace, req.params.id, req.body.score, JSON.parse(req.body.tags), function(reply) {
        _replyJSON(req, res, reply);
      });
    });
    app.del(DEFAULT_ROUTE + "/id/:namespace/:id", function(req, res) {
      rt.remove(req.params.namespace, req.params.id, function(reply) {
        _replyJSON(req, res, reply);
      });
    });
    app.get(DEFAULT_ROUTE + "/id/:namespace/:id", function(req, res) {
      rt.get(req.params.namespace, req.params.id, function(reply) {
        _replyJSON(req, res, reply);
      });
    });
    app.get(DEFAULT_ROUTE + "/allids/:namespace", function(req, res) {
      rt.allids(req.params.namespace, function(reply) {
        _replyJSON(req, res, reply);
      });
    });
    app.get(DEFAULT_ROUTE + "/toptags/:namespace/:amount", function(req, res) {
      rt.toptags(req.params.namespace, req.params.amount, function(reply) {
        _replyJSON(req, res, reply);
      });
    });
    app.get(DEFAULT_ROUTE + "/tags/:namespace", function(req, res) {
      var p, u;
      u = qs.parse(url.parse(req.url).query);
      p = {
        tags: JSON.parse(u.tags),
        limit: u.limit,
        offset: u.offset,
        withscores: u.withscores,
        order: u.order,
        type: u.type,
        callback: function(reply) {
          _replyJSON(req, res, reply);
        }
      };
      rt.tags(req.params.namespace, p);
    });
  };
  connect.createServer(connect.bodyParser(), connect.logger(), connect.router(redis_tagger)).listen(PORT);
}).call(this);
