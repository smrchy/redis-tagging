PORT = 8010
DEFAULT_ROUTE = "/tagger"
NAMESPACE_PREFIX = "tgs:"

connect = require "connect"
url = require "url"
qs = require "querystring"
redisclient = require "redis"
redis = redisclient.createClient(6379, "192.168.11.24")
RedisTagging = require("./redis-tagging").multi_namespace

rt =  new RedisTagging redis, NAMESPACE_PREFIX

redis_tagger = (app) ->
	_replyJSON = (req, res, reply) ->
		u = qs.parse url.parse(req.url).query
		if u.callback
			res.writeHead 200,
				"Content-Type": "application/javascript; charset=UTF-8"
			res.end(u.callback + '(' + JSON.stringify(reply) + ');')
		else
			res.writeHead 200,
				"Content-Type": "application/json; charset=UTF-8"
			res.end JSON.stringify(reply)
		return

	# Set the tags for a id
	# 
	# POST /tagger/id/:namespace/:id
	# 
	# :namespace is the global key / appname for this tagging namespace and :id is the primary key of the item being tagged. 
	#
	# Form-fields:
	# * score (Int)
	# * tags (String) a JSON array of tags
	app.post DEFAULT_ROUTE + "/id/:namespace/:id", (req, res) ->
		rt.set req.params.namespace, req.params.id, req.body.score, JSON.parse(req.body.tags), (reply) ->
			_replyJSON(req, res, reply)
			return
		return

	# Delete an id
	app.del DEFAULT_ROUTE + "/id/:namespace/:id", (req, res) ->
		rt.remove req.params.namespace, req.params.id, (reply) ->
			_replyJSON(req, res, reply)
			return
		return

	# Get all tags for an ID
	app.get DEFAULT_ROUTE + "/id/:namespace/:id", (req, res) ->
		rt.get req.params.namespace, req.params.id, (reply) ->
			_replyJSON(req, res, reply)
			return
		return

	# Get all IDs for a namespace
	app.get DEFAULT_ROUTE + "/allids/:namespace", (req, res) ->
		rt.allids req.params.namespace, (reply) ->
			_replyJSON(req, res, reply)
			return
		return

	# Get the top tags for 
	app.get DEFAULT_ROUTE + "/toptags/:namespace/:amount", (req, res) ->
		rt.toptags req.params.namespace, req.params.amount, (reply) ->
			_replyJSON(req, res, reply)
			return
		return	

	# Get all IDs for one or more tags
	app.get DEFAULT_ROUTE + "/tags/:namespace", (req, res) ->
		u = qs.parse url.parse(req.url).query

		p = 
			tags: JSON.parse(u.tags)
			limit: u.limit
			offset: u.offset
			withscores: u.withscores
			order: u.order
			type: u.type
			callback: (reply) ->
				_replyJSON(req, res, reply)
				return
		rt.tags req.params.namespace, p 
		return

	# Get all namespaces
	app.get DEFAULT_ROUTE + "/namespaces", (req, res) ->
		rt.namespaces((reply) ->
			_replyJSON(req, res, reply)
		)
		return

	# Delete a single namespace
	app.del DEFAULT_ROUTE + "/namespace/:namespace", (req, res) ->
		rt.removens req.params.namespace, (reply) ->
			_replyJSON(req, res, reply)
			return
		return

	return


connect.createServer(
	connect.bodyParser()
	connect.logger()
	connect.router redis_tagger
).listen PORT