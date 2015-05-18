should = require "should"
RedisTagging = require "../index" 
_ = require "lodash"

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
		it 'Set tags for an item with non numeric score: FAILS', (done) ->
			rt.set {bucket: bucket1, id: "123", score: "dfgs", tags: ["just","testing"]}, (err, resp) ->
				err.message.should.equal("Invalid score format")
				done()
				return
			return

		it 'Set tags for an item with tags missing: FAILS', (done) ->
			rt.set {bucket: bucket1, id: "123"}, (err, resp) ->
				err.message.should.equal("No tags supplied")
				done()
				return
			return

		it 'Set tags for an item with tags not being an array: FAILS', (done) ->
			rt.set {bucket: bucket1, id: "123", tags: "string..."}, (err, resp) ->
				err.message.should.equal("Invalid tags format")
				done()
				return
			return

		it 'Set tags for an item "123" but do not supply a single tag', (done) ->
			rt.set {bucket: bucket1, id: "123", tags: []}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return

		it 'Set tags for an item "123"', (done) ->
			rt.set {bucket: bucket1, id: "123", tags: ["just","testing"]}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return

		it 'Get tags without supplying an id', (done) ->
			rt.get {bucket: bucket1}, (err, resp) ->
				err.message.should.equal("No id supplied")
				done()
				return
			return

		it 'Get tags without supplying a bucket or id', (done) ->
			rt.get {}, (err, resp) ->
				err.message.should.equal("No bucket supplied")
				done()
				return
			return


		it 'Get tags for this item "123"', (done) ->
			rt.get {bucket: bucket1, id: "123"}, (err, resp) ->
				should.not.exist(err)
				resp.should.containEql('just')
				resp.should.containEql('testing')
				done()
				return
			return

		it 'Delete this item "123"', (done) ->
			rt.remove {bucket: bucket1, id: "123"}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return

		it 'Make sure this item is gone "123"', (done) ->
			rt.get {bucket: bucket1, id: "123"}, (err, resp) ->
				should.not.exist(err)
				resp.length.should.equal(0)
				done()
				return
			return

		it 'Get all IDs for this bucket: []', (done) ->
			rt.allids {bucket: bucket1}, (err, resp) ->
				should.not.exist(err)
				resp.length.should.equal(0)
				done()
				return
			return

		it 'Set tags for an item, again "123"', (done) ->
			rt.set {bucket: bucket1, id: "123", score: 10, tags: ["just", "testing", "all"]}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return

		it 'Get all IDs for this bucket: ["123"]', (done) ->
			rt.allids {bucket: bucket1}, (err, resp) ->
				should.not.exist(err)
				resp.length.should.equal(1)
				resp[0].should.equal("123")
				done()
				return
			return

		it 'Set tags for an item with extended chars "456"', (done) ->
			rt.set {bucket: bucket1, id: "456", score: 10, tags: ["äöüÖÄÜ§$%& ,.-+#áéóíáà~","   testing   ", "all"]}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return

		it 'Get tags for this item "456"', (done) ->
			rt.get {bucket: bucket1, id: "456"}, (err, resp) ->
				should.not.exist(err)
				resp.should.containEql('äöüÖÄÜ§$%& ,.-+#áéóíáà~')
				resp.should.containEql('   testing   ')
				done()
				return
			return
		
		it 'Get all IDs for this bucket: ["123","456"]', (done) ->
			rt.allids {bucket: bucket1}, (err, resp) ->
				should.not.exist(err)
				resp.length.should.equal(2)
				resp.should.containEql("123")
				resp.should.containEql("456")
				done()
				return
			return

		it 'Get all IDs for the tag []: []', (done) ->
			rt.tags {bucket: bucket1, tags:[]}, (err, resp) ->
				should.not.exist(err)
				resp.total_items.should.equal(0)
				resp.limit.should.equal(100)
				resp.offset.should.equal(0)
				resp.items.should.be.empty
				done()
				return
			return

		it 'Get all IDs for the tag ["testing"]: ["123"]', (done) ->
			rt.tags {bucket: bucket1, tags:["testing"]}, (err, resp) ->
				should.not.exist(err)
				resp.total_items.should.equal(1)
				resp.limit.should.equal(100)
				resp.offset.should.equal(0)
				resp.items.should.containEql("123")
				done()
				return
			return

		it 'Get all IDs for the tag ["all"]: ["123", "456"]', (done) ->
			rt.tags {bucket: bucket1, tags:["all"]}, (err, resp) ->
				should.not.exist(err)
				resp.total_items.should.equal(2)
				resp.limit.should.equal(100)
				resp.offset.should.equal(0)
				resp.items.should.containEql("123")
				resp.items.should.containEql("456")
				done()
				return
			return

		it 'Get all IDs for the tag ["all"] with limit:0', (done) ->
			rt.tags {bucket: bucket1, tags:["all"], limit:0}, (err, resp) ->
				should.not.exist(err)
				resp.total_items.should.equal(2)
				resp.items.length.should.equal(0)
				done()
				return
			return

		it 'Get all IDs for the tag intersection ["all","testing"]: ["123"]', (done) ->
			rt.tags {bucket: bucket1, tags:["all","testing"]}, (err, resp) ->
				should.not.exist(err)
				resp.total_items.should.equal(1)
				resp.limit.should.equal(100)
				resp.offset.should.equal(0)
				resp.items.should.containEql("123")
				done()
				return
			return

		it 'Get all IDs for the tag intersection ["all","testing"]: ["123"]', (done) ->
			rt.tags {bucket: bucket1, tags:["all","testing"], type: "union"}, (err, resp) ->
				should.not.exist(err)
				resp.total_items.should.equal(2)
				resp.limit.should.equal(100)
				resp.offset.should.equal(0)
				resp.items.should.containEql("123","456")
				done()
				return
			return

		it 'Get the 2 toptags', (done) ->
			rt.toptags {bucket: bucket1, amount: 2}, (err, resp) ->
				should.not.exist(err)
				resp.total_items.should.equal(5)
				resp.items[0].tag.should.equal("all")
				resp.items[0].count.should.equal(2)
				done()
				return
			return

		it 'Get all buckets', (done) ->
			rt.buckets (err, resp) ->
				should.not.exist(err)
				resp.should.containEql("test")
				done()
				return
			return

		return
	describe 'CLEANUP', ->
		it 'Remove bucket "test"', (done) ->
			rt.removebucket {bucket: bucket1}, (err, resp) ->
				should.not.exist(err)
				resp.should.equal(true)
				done()
				return
			return

	return