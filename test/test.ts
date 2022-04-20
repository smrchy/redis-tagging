import "mocha";
import should from "should";
import RedisTagging from "../index";

describe("Redis-Tagging Test", async () => {
	let rt: RedisTagging = null;
	const bucket1 = "test";
	const bucket2 = "TEST";

	before(async () => {
		rt = new RedisTagging();
		await rt.connect();
	});

	after(async () => {
		await rt.quit();
	});

	describe("Basics", () => {
		it("Set tags for an item with non numeric score: FAILS", async () => {
			try {
				await rt.set({
					bucket: bucket1,
					id: "123",
					score: "dfgs",
					tags: ["just", "testing"],
				});
			} catch (err) {
				should(err.message).equal("Invalid score format");
				return;
			}
			throw new Error("Should have thrown an error");
		});

		it("Set tags for an item with tags missing: FAILS", async () => {
			try {
				// @ts-ignore
				await rt.set({ bucket: bucket1, id: "123" });
			} catch (err) {
				err.message.should.equal("No tags supplied");
				return;
			}
			throw new Error("Should have thrown an error");
		});

		it("Set tags for an item with tags not being an array: FAILS", async () => {
			try {
				// @ts-ignore
				await rt.set({ bucket: bucket1, id: "123", tags: "string..." });
			} catch (err) {
				err.message.should.equal("Invalid tags format");
				return;
			}
			throw new Error("Should have thrown an error");
		});

		it("Set tags for an item '123' but do not supply a single tag", async () => {
			const resp = await rt.set({ bucket: bucket1, id: "123", tags: [] });
			resp.should.equal(true);
		});

		it("Set tags for an item '123'", async () => {
			const resp = await rt.set({
				bucket: bucket1,
				id: "123",
				tags: ["just", "testing"],
			});
			resp.should.equal(true);
		});

		it("Get tags without supplying an id", async () => {
			try {
				// @ts-ignore
				await rt.get({ bucket: bucket1 });
			} catch (err) {
				err.message.should.equal("No id supplied");
				return;
			}
			throw new Error("Should have thrown an error");
		});

		it("Get tags without supplying a bucket or id", async () => {
			try {
				// @ts-ignore
				await rt.get({});
			} catch (err) {
				err.message.should.equal("No bucket supplied");
				return;
			}
			throw new Error("Should have thrown an error");
		});

		it("Get tags for this item '123'", async () => {
			const resp = await rt.get({ bucket: bucket1, id: "123" });
			resp.should.containEql("just");
			resp.should.containEql("testing");
		});

		it("Delete this item '123'", async () => {
			const resp = await rt.remove({ bucket: bucket1, id: "123" });
			resp.should.equal(true);
		});

		it("Make sure this item is gone '123'", async () => {
			const resp = await rt.get({ bucket: bucket1, id: "123" });

			resp.length.should.equal(0);
		});

		it("Get all IDs for this bucket: []", async () => {
			const resp = await rt.allids({ bucket: bucket1 });

			resp.length.should.equal(0);
		});

		it("Set tags for an item, again '123'", async () => {
			const resp = await rt.set({
				bucket: bucket1,
				id: "123",
				score: 10,
				tags: ["just", "testing", "all"],
			});

			resp.should.equal(true);
		});

		it("Get all IDs for this bucket: ['123']", async () => {
			const resp = await rt.allids({ bucket: bucket1 });

			resp.length.should.equal(1);
			resp[0].should.equal("123");
		});

		it("Set tags for an item with extended chars '456'", async () => {
			const resp = await rt.set({
				bucket: bucket1,
				id: "456",
				score: 10,
				tags: ["äöüÖÄÜ§$%& ,.-+#áéóíáà~", "   testing   ", "all"],
			});

			resp.should.equal(true);
		});

		it("Get tags for this item '456'", async () => {
			const resp = await rt.get({ bucket: bucket1, id: "456" });

			resp.should.containEql("äöüÖÄÜ§$%& ,.-+#áéóíáà~");
			resp.should.containEql("   testing   ");
		});

		it("Get all IDs for this bucket: ['123','456']", async () => {
			const resp = await rt.allids({ bucket: bucket1 });

			resp.length.should.equal(2);
			resp.should.containEql("123");
			resp.should.containEql("456");
		});

		it("Get all IDs for the tag []: []", async () => {
			const resp = await rt.tags({ bucket: bucket1, tags: [] });

			resp.total_items.should.equal(0);
			resp.limit.should.equal(100);
			resp.offset.should.equal(0);
			resp.items.should.be.empty;
		});

		it("Get all IDs for the tag ['testing']: ['123']", async () => {
			const resp = await rt.tags({ bucket: bucket1, tags: ["testing"] });

			resp.total_items.should.equal(1);
			resp.limit.should.equal(100);
			resp.offset.should.equal(0);
			resp.items.should.containEql("123");
		});

		it("Get all IDs for the tag ['all']: ['123', '456']", async () => {
			const resp = await rt.tags({ bucket: bucket1, tags: ["all"] });

			resp.total_items.should.equal(2);
			resp.limit.should.equal(100);
			resp.offset.should.equal(0);
			resp.items.should.containEql("123");
			resp.items.should.containEql("456");
		});

		it("Get all IDs for the tag ['all'] with limit:0", async () => {
			const resp = await rt.tags({
				bucket: bucket1,
				tags: ["all"],
				limit: 0,
			});

			resp.total_items.should.equal(2);
			resp.items.length.should.equal(0);
		});

		it("Get all IDs for the tag intersection ['all','testing']: ['123']", async () => {
			const resp = await rt.tags({
				bucket: bucket1,
				tags: ["all", "testing"],
			});

			resp.total_items.should.equal(1);
			resp.limit.should.equal(100);
			resp.offset.should.equal(0);
			resp.items.should.containEql("123");
		});

		it("Get all IDs for the tag intersection ['all','testing']: ['123']", async () => {
			const resp = await rt.tags({
				bucket: bucket1,
				tags: ["all", "testing"],
				type: "union",
			});

			resp.total_items.should.equal(2);
			resp.limit.should.equal(100);
			resp.offset.should.equal(0);
			resp.items.should.containEql("123");
			resp.items.should.containEql("456");
		});

		it("Get the 2 toptags", async () => {
			const resp = await rt.toptags({ bucket: bucket1, amount: 2 });

			resp.total_items.should.equal(5);
			resp.items[0].tag.should.equal("all");
			resp.items[0].count.should.equal(2);
		});

		it("Get all buckets", async () => {
			const resp = await rt.buckets();

			resp.should.containEql("test");
		});
	});

	describe("CLEANUP", () => {
		it("Remove bucket 'test'", async () => {
			const resp = await rt.removebucket({ bucket: bucket1 });

			resp.should.equal(true);
		});
	});
});
