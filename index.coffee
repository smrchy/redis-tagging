###
Redis Tagging

The MIT License (MIT)

Copyright © 2013 Patrick Liess, http://www.tcs.de

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
###

RedisInst = require "redis"

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
#	* `nsprefix`: *optional* Default: "rt". The namespace prefix for all Redis keys used by this module.
#
class RedisTagging

	constructor: (options={}) ->
		@redisns = options.namespace or "rt"
		@redisns = @redisns + ":"
		
		port = options.port or 6379
		host = options.host or "127.0.0.1"

		@redis = RedisInst.createClient(port, host)


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
				# Clean up the TAGCOUNT
				mc.push( [ 'zremrangebyscore', ns + ':TAGCOUNT', 0, 0] )
			# Return to the caller with the Multi-Command array
			cb(mc)
			return
		return

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
		ns = @redisns + options.bucket
		@redis.smembers "#{ns}:ID:#{options.id}", (err, resp) ->
			if err
				cb(err)
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
	# *	`score` (Number)
	# *	`tags` (Array)
	#
	set: (options, cb) =>
		ns = @redisns + options.bucket
		id_index = ns + ':ID:' + options.id
		# First delete this ID from the DB. We will recreate it from scratch
		@_deleteID ns, options.id, (mc) =>
			# mc contains the delete commands for this tag. Now we add add this item again with all new tags
			for tag in options.tags
				mc.push( [ 'zincrby', ns + ':TAGCOUNT', 1, tag ] )
				mc.push( [ 'sadd', id_index, tag ] )
				mc.push( [ 'zadd', ns  + ':TAGS:' + tag, options.score, options.id ] )
			@redis.multi(mc).exec (err, resp) ->
				cb(null, true)
				return
			return
		return

	# Remove
	#
	# Delete an ID (we use remove because delete is a reserved word in JS)
	remove: (namespace, id, callback) =>
		ns = @redisns + namespace
		@_deleteID ns, id, (mc) =>
			if mc.length
				@redis.multi(mc).exec (err, resp) ->
					callback({ok: true})
					return
			else
				callback({ok: true})
			return
		return
	


	
	# ## AllIDs
	#
	# Get all IDs for a namespace
	allids: (namespace, callback) =>
		prefix = @nsprefix + namespace + ':ID:'
		@redis.keys prefix + '*', (err, resp) ->
			_prefix_len = prefix.length
			rows = for e in resp
				e.substr(_prefix_len)
			o = 
				total_rows: rows.length
				rows: rows
			callback o 
			return
		return

	# ## Tags
	# 
	# Return the IDs of an intersection of two or more tags
	#
	# Parameters (Object)
	# * tags (Array) One or more tags
	# * limit (Number) Default = 100 (0 will return 0 rows but will return the total_rows!)
	# * offset (Number) Default = 0
	# * withscores (Number) Default = 0 Set this to 1 to output the scores
	# * order (String) Default ="desc"
	# * type (String) "inter", "union" Default: "inter"
	# * callback (Function)
	tags: (namespace, p) =>
		ns = @nsprefix + namespace
		p = 
			tags: p.tags,
			limit: Number(p.limit or 100)
			offset: Number(p.offset or 0)
			withscores: Number(p.withscores) or 0
			order: if p.order is "asc" then "" else "rev"
			type: (p.type or "inter").toLowerCase()
			callback: p.callback

		prefix = ns + ':TAGS:'
		# The last element to get
		lastelement = p.offset + p.limit - 1
		mc = []

		# Intersection and Union of multiple tags
		if p.tags.length > 1

			rndkey = ns + (new Date().getTime()) + '_' + Math.floor(Math.random()*9999999999)
			
			# Create the Redis keys from the supplied tags
			_keys = for tag in p.tags
				prefix + tag

			# Create a temporary Redis key with the result
			mc.push [ 'z' + p.type + 'store', rndkey, _keys.length]
				.concat(_keys)
				.concat( [ 'AGGREGATE', 'MIN' ] )

			# If limit is 0 we don't need to return results. Just the total_rows
			if p.limit > 0 
				resultkey = rndkey
			
		# Single tag
		else if p.tags.length is 1
			# Just count the amount of IDs for this tag
			mc.push ['zcard', prefix + p.tags[0]]
			if p.limit > 0
				resultkey = prefix + p.tags[0]

		
		# Now run the Redis query
		if mc.length
			# Get the IDs
			if p.limit > 0
				tagsresult = [ 'z' + p.order + 'range', resultkey, p.offset, lastelement ]
				if p.withscores
					tagsresult = tagsresult.concat( ['WITHSCORES'] )
				mc.push( tagsresult )
			# Delete the temp key if this was an intersection or union
			if p.tags.length > 1
				mc.push( ['del', rndkey] )
			@redis.multi(mc).exec (err,resp) ->
				# We don't have resp[1] is limit = 0. We just return an empty array then
				if p.limit is 0
					rows = []
				else
					rows = resp[1]
				if rows.length and p.withscores
					rows = for e,i in rows by 2
						{id: e, score: rows[i+1]}
				p.callback
					total_rows: resp[0]
					rows: rows
					limit: p.limit
					offset: p.offset
				return
		else
			p.callback({"error":"Supply at least one tag"})
		return
	
	# TopTags
	#
	# * namespace (String)
	# * amount (Int) (0 returns all)
	toptags: (namespace, amount, callback) =>
		ns = @nsprefix + namespace
		amount = Math.abs(amount) - 1
		rediskey = ns + ':TAGCOUNT'
		@redis.zcard rediskey, (err, resp) =>
			total_rows = resp
			@redis.zrevrange rediskey, 0, amount, 'WITHSCORES', (err, resp) ->
				rows = for e,i in resp by 2
					tag: e, count: Number(resp[i+1])
				o = 
					total_rows: total_rows
					rows: rows	
				callback(o)
				return
			return
		return

	# Namespaces
	#
	namespaces: (callback) =>
		@redis.keys @nsprefix + "*" + ":TAGCOUNT", (err, resp) =>
			ns = for e in resp
				e.substr(@nsprefix.length,(e.length - @nsprefix.length - ":TAGCOUNT".length))
			callback({namespaces:ns})
			return
		return

	# Remove a namespace and all its keys
	#
	removens: (namespace, callback) =>
		@redis.keys @nsprefix + namespace + '*', (err, resp) =>
			if resp.length
				@redis.del resp, (err, resp) =>
					callback({ok: true, keys: resp})
					return
				return
			callback({ok: true, keys: 0})
			return
		return
		

module.exports = RedisTagging