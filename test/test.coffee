should = require "should"
RedisTagging = require "../index" 

describe 'Redis-Tagging Test', ->
	rt = null
	bucket1 = "test"
	bucket2 = "TEST"

	before (done) ->
		done()
		return

	after (done) ->
		done()		
		return
	

	it 'get a RedisTagging instance', (done) ->
		rt = new RedisTagging()
		rt.should.be.an.instanceOf RedisTagging
		done()
		return

	describe 'Basics', ->
		it 'Set tags for an item', (done) ->
			rt.set {bucket: bucket1, id: "123", score: 10, tags: ["just","testing"]}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return
		it 'Get tags for this item', (done) ->
			rt.get {bucket: bucket1, id: "123"}, (err, resp) ->
				should.not.exist(err)
				resp.should.include('just')
				resp.should.include('testing')
				done()
				return
			return
		it 'Set tags for an item with extended chars', (done) ->
			rt.set {bucket: bucket1, id: "456", score: 10, tags: ["äöüÖÄÜ§$%& ,.-+#áéóíáà~","   testing   "]}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return
		it 'Get tags for this item', (done) ->
			rt.get {bucket: bucket1, id: "456"}, (err, resp) ->
				should.not.exist(err)
				resp.should.include('äöüÖÄÜ§$%& ,.-+#áéóíáà~')
				resp.should.include('   testing   ')
				done()
				return
			return


		return
	describe 'CLEANUP', ->
		
		it 'Remove all data', (done) ->
			done()
			return
	
	return