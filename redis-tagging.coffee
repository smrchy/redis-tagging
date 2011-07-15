###
Redis-Tagging
A tagging helper library for NodeJS and Redis
Version 0.2
Copyright (c) 2011 TCS    dev (at) tcs.de
Released under the MIT License
###

class RedisTagging
	constructor: (@redis, @nsprefix) ->

	# Return an array with Redis commands to delete an ID, all tag connections and update the counters 
	_deleteID: (ns, id, callback) =>
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
			callback(mc)
			return
		return

	# ## Set
	# 
	# Set (insert or update) an ID
	# 
	# * id (String)
	# * score (Number)
	# * tags (Array)
	set: (namespace, id, score, tags, callback) =>
		ns = @nsprefix + namespace
		id_index = ns + ':ID:' + id
		# First delete this ID from the DB. We will recreate it from scratch
		@_deleteID ns, id, (mc) =>
			# mc contains the delete commands for this tag. Now we add add this item again with all new tags
			for tag in tags
				mc.push( [ 'zincrby', ns + ':TAGCOUNT', 1, tag ] )
				mc.push( [ 'sadd', id_index, tag ] )
				mc.push( [ 'zadd', ns  + ':TAGS:' + tag, score, id ] )
			@redis.multi(mc).exec (err, resp) ->
				callback({ok: true})
				return
			return
		return

	# Remove
	#
	# Delete an ID (we use remove because delete is a reserved word in JS)
	remove: (namespace, id, callback) =>
		ns = @nsprefix + namespace
		@_deleteID ns, id, (mc) =>
			if mc.length
				@redis.multi(mc).exec (err, resp) ->
					callback({ok: true})
					return
			else
				callback({ok: true})
			return
		return
	

	# ## Get
	#
	# Get all tags for an ID
	get: (namespace, id, callback) =>
		ns = @nsprefix + namespace
		@redis.smembers ns + ':ID:' + id, (req, resp) ->
			tags = for tag in resp
				tag
			callback tags 
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
		

	
# Class to use Redis-Tagging with a single namespace
class RedisTaggingSingleNS extends RedisTagging
	constructor: (@redis, @nsprefix, @namespace) ->

	set: (id, score, tags, callback) =>
		super @namespace, id, score, tags, callback
		return

	get: (id, callback) =>
		super @namespace, id, callback
		return

	remove: (id, callback) =>
		super @namespace, id, callback
		return

	allids: (callback) =>
		super @namespace, callback
		return

	tags: (p) =>
		super @namespace, p
		return

	toptags: (amount) =>
		super @namespace, amount
		return


exports.multi_namespace = RedisTagging
exports.single_namespace = RedisTaggingSingleNS