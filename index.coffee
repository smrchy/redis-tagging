###
Redis Tagging

The MIT License (MIT)

Copyright © 2013 Patrick Liess, http://www.tcs.de

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
###

RedisInst 	= require "redis"
_template 	= require "lodash/template"
_isNaN 		= require "lodash/isNaN"
_isArray 	= require "lodash/isArray"
_isNumber 	= require "lodash/isNumber"
_isString	= require "lodash/isString"

# # Redis Tagging
#
# To create a new instance use:
#
# 	RedisTagging = require("redis-tagging")
#	rt = new RedisTagging()
#
#	Parameters via an `options` object:
#
#	* `port`: *optional* Default: 6379. The Redis port.
#	* `host`, *optional* Default: "127.0.0.1". The Redis host.
#   * `options`, *optional* Default: {}. Additional options. 
#	* `nsprefix`: *optional* Default: "rt". The namespace prefix for all Redis keys used by this module.
#	* `client`: *optional* An external RedisClient object which will be used for the connection.
#
class RedisTagging

	constructor: (o={}) ->
		@redisns = (o.nsprefix or "rt") + ":"
		port = o.port or 6379
		host = o.host or "127.0.0.1"
		options = o.options or {}

		if o.client?.constructor?.name is "RedisClient"
			@redis = o.client
		else
			@redis = RedisInst.createClient(port, host, options)

		@_initErrors()


	# ## Get
	#
	# Get all tags for an ID
	#
	# Parameters object:
	#
	# * `bucket` (String)
	# * `id` (String)
	#
	get: (options, cb) =>
		if @_validate(options, ["bucket", "id"], cb) is false
			return
		ns = @redisns + options.bucket
		@redis.smembers "#{ns}:ID:#{options.id}", (err, resp) =>
			if err
				@_handleError(cb, err)
				return
			tags = for tag in resp
				tag
			cb(null, tags)
			return
		return


	# ## Set
	# 
	# Set (insert or update) an item
	# 
	# Parameters object:
	#
	# * `bucket` (String)
	# * `id` (String)
	# *	`tags` (Array)
	# *	`score` (Number) *optional* Default: 0
	#
	# Returns `true` when the item was set.
	#
	set: (options, cb) =>
		if @_validate(options, ["bucket", "id", "score", "tags"], cb) is false
			return
		ns = @redisns + options.bucket
		id_index = ns + ':ID:' + options.id
		# First delete this ID from the DB. We will recreate it from scratch
		@_deleteID ns, options.id, (mc) =>
			# mc contains the delete commands for this tag. Now we add add this item again with all new tags
			for tag in options.tags
				mc.push( [ 'zincrby', ns + ':TAGCOUNT', 1, tag ] )
				mc.push( [ 'sadd', id_index, tag ] )
				mc.push( [ 'zadd', ns  + ':TAGS:' + tag, options.score, options.id ] )
			if options.tags.length
				mc.push( [ 'sadd', ns + ':IDS', options.id ] )
			if mc.length is 0
				cb(null, true)
				return
			@redis.multi(mc).exec (err, resp) =>
				if err
					@_handleError(cb, err)
					return
				cb(null, true)
				return
			return
		return


	# ## Remove
	#
	# Remove / Delete an item
	#
	# Parameters object:
	#
	# * `bucket` (String)
	# * `id` (String)
	#
	# Returns `true` even if that id did not exist.
	#
	remove: (options, cb) =>
		options.tags = []
		
		@set(options, cb)
		
		return
	
	# ## AllIDs
	#
	# Get all IDs for a single bucket
	#
	# Parameters object:
	#
	# * `bucket` (String)
	#
	# Returns an array of item ids
	#
	allids: (options, cb) =>
		if @_validate(options, ["bucket"], cb) is false
			return
		ns = @redisns + options.bucket
		@redis.smembers ns + ":IDS", (err, resp) =>
			if err
				@_handleError(cb, err)
				return
			cb(null, resp)
			return
		return

	# ## Tags
	# 
	# Return the IDs of an either a single tag or an intersection/union of two or more tags 
	#
	# Parameters object:
	#
	# * `bucket` (String)
	# * `tags` (Array) One or more tags
	# * `limit` (Number) *optional* Default=100 (0 will return 0 items but will return the total_items!)
	# * `offset` (Number) *optional* Default=0
	# * `withscores` (Number) *optional* Default=0 Set this to 1 to output the scores
	# * `order` (String) *optional* Default ="desc"
	# * `type` (String) *optional* "inter", "union" Default: "inter"
	#
	tags: (options, cb) =>
		if @_validate(options, ["bucket", "tags", "offset", "limit", "withscores", "type", "order"], cb) is false
			return
		ns = @redisns + options.bucket
			
		prefix = ns + ':TAGS:'
		# The last element to get
		lastelement = options.offset + options.limit - 1
		mc = []

		# Bail if no tags supplied
		if options.tags.length is 0
			cb( null,
				total_items: 0
				items: []
				limit: options.limit
				offset: options.offset
			)
			return
		# Intersection and Union of multiple tags
		if options.tags.length > 1

			rndkey = ns + (new Date().getTime()) + '_' + Math.floor(Math.random()*9999999999)
			
			# Create the Redis keys from the supplied tags
			_keys = for tag in options.tags
				prefix + tag

			# Create a temporary Redis key with the result
			mc.push [ 'z' + options.type + 'store', rndkey, _keys.length].concat(_keys).concat( [ 'AGGREGATE', 'MIN' ] )

			# If limit is 0 we don't need to return results. Just the total_rows
			if options.limit > 0 
				resultkey = rndkey
			
		# Single tag
		else if options.tags.length is 1
			# Just count the amount of IDs for this tag
			mc.push ['zcard', prefix + options.tags[0]]
			if options.limit > 0
				resultkey = prefix + options.tags[0]

		
		# Now run the Redis query
		# Get the IDs
		if options.limit > 0
			tagsresult = [ 'z' + options.order + 'range', resultkey, options.offset, lastelement ]
			if options.withscores
				tagsresult = tagsresult.concat( ['WITHSCORES'] )
			mc.push( tagsresult )
		# Delete the temp key if this was an intersection or union
		if options.tags.length > 1
			mc.push( ['del', rndkey] )
		@redis.multi(mc).exec (err, resp) =>
			if err
				@_handleError(cb, err)
				return
			# We don't have resp[1] is limit = 0. We just return an empty array then
			if options.limit is 0
				rows = []
			else
				rows = resp[1]
			if rows.length and options.withscores
				rows = for e,i in rows by 2
					{id: e, score: rows[i+1]}
			cb( null,
				total_items: resp[0]
				items: rows
				limit: options.limit
				offset: options.offset
			)
			return

		return
	

	# TopTags
	#
	# Parameters object:
	#
	# * `bucket` (String)
	# * `amount` (Number) *optional* Default=0 (0 returns all)
	#
	toptags: (options, cb) =>
		if @_validate(options, ["bucket", "amount"], cb) is false
			return
		ns = @redisns + options.bucket
		options.amount = options.amount - 1
		rediskey = ns + ':TAGCOUNT'
		mc = [
			["zcard", rediskey]
			["zrevrange", rediskey, 0, options.amount, "WITHSCORES"]
		]

		@redis.multi(mc).exec (err, resp) =>
			if err
				@_handleError(cb, err)
				return

			rows = for e,i in resp[1] by 2
				tag: e, count: Number(resp[1][i+1])
			cb(null,
				total_items: resp[0]
				items: rows
			)
			return
		return


	# Buckets
	#
	# Returns all buckets.
	# Use with care: Uses redis.keys 
	#
	# Returns an array with all buckets
	#
	buckets: (cb) =>
		@redis.keys @redisns + "*" + ":TAGCOUNT", (err, resp) =>
			if err
				@_handleError(cb, err)
				return
			o = for e in resp
				e.substr(@redisns.length,(e.length - @redisns.length - ":TAGCOUNT".length))
			cb(null, o)
			return
		return


	# Remove a bucket and all its keys
	#
	# Use with care: Uses redis.keys 
	#
	# Parameters object:
	#
	# * `bucket`(String)
	#
	removebucket: (options, cb) =>
		if @_validate(options, ["bucket"], cb) is false
			return
		ns = @redisns + options.bucket
		mc = [
			["smembers", ns + ":IDS"]
			["zrange", ns + ":TAGCOUNT", 0, -1]
		]
		@redis.multi(mc).exec (err, resp) =>
			if err
				@_handleError(cb, err)
				return
			rkeys = [
				ns + ":IDS"
				ns + ":TAGCOUNT"
			]
			for e in resp[0]
				rkeys.push(ns + ":ID:" + e)
			for e in resp[1]
				rkeys.push(ns + ":TAGS:" + e)
			@redis.del rkeys, (err, resp) =>
				cb(null, true)
				return
			return
		return


	# Helpers

	# Return an array with Redis commands to delete an ID, all tag connections and update the counters 
	_deleteID: (ns, id, cb) =>
		mc = []
		id_index = ns + ':ID:' + id
		@redis.smembers id_index, (err, resp) =>
			if resp.length
				# This ID already has tags. We will delete them first
				for tag in resp
					mc.push( [ 'zincrby', ns + ':TAGCOUNT', -1, tag ] )
					mc.push( [ 'zrem', ns + ':TAGS:' + tag, id] )
				# Also delete the index for this ID
				mc.push( [ 'del', id_index ] )
				# Delete the id in the IDS list
				mc.push( [ 'srem', ns + ':IDS', id ] )
				# Clean up the TAGCOUNT
				mc.push( [ 'zremrangebyscore', ns + ':TAGCOUNT', 0, 0] )
			# Return to the caller with the Multi-Command array
			cb(mc)
			return
		return

	_handleError: (cb, err, data={}) =>
		# try to create a error Object with humanized message
		if _isString(err)
			_err = new Error()
			_err.name = err
			_err.message = @_ERRORS?[err]?(data) or "unkown"
		else 
			_err = err
		cb(_err)
		return


	_initErrors: =>
		@_ERRORS = {}
		for key, msg of @ERRORS
			@_ERRORS[key] = _template(msg)
		return

	_VALID:
		bucket:	/^([a-zA-Z0-9_-]){1,80}$/
     
	_validate: (o, items, cb) ->
		for item in items
			# General checks
			switch item
				when "bucket", "id", "tags"
					if not o[item]
						@_handleError(cb, "missingParameter", {item:item})
						return false
				when "score"
					o[item] = parseInt(o[item] or 0, 10)
				when "limit"
					if not _isNumber(o[item]) or _isNaN(o[item])
						o[item] = 100
					o[item] = Math.abs(parseInt(o[item], 10))
				when "offset", "withscores", "amount"
					o[item] = Math.abs(parseInt(o[item] or 0, 10))
				when "order"
					o[item] = if o[item] is "asc" then "" else "rev"
				when "type"
					if o[item] and o[item].toLowerCase() is "union"
						o[item] = "union"
					else
						o[item] = "inter"
						

			switch item
				when "bucket"
					o[item] = o[item].toString()
					if not @_VALID[item].test(o[item])
						@_handleError(cb, "invalidFormat", {item:item})
						return false
				when "id"
					o[item] = o[item].toString()
					if not o[item].length
						@_handleError(cb, "missingParameter", {item:item})
						return false
				when "score", "limit", "offset", "withscores", "amount"
					if _isNaN(o[item])
						@_handleError(cb, "invalidFormat", {item:item})
						return false
				when "tags"
					if not _isArray(o[item]) 
						@_handleError(cb, "invalidFormat", {item:item})
						return false

		return o


	ERRORS:
		"missingParameter": "No <%= item %> supplied"
		"invalidFormat": "Invalid <%= item %> format"
		
module.exports = RedisTagging