import { createClient, RedisClientOptions } from "redis";
import RedisClient from "@node-redis/client/dist/lib/client";
import { RedisTaggingOptions, IInputOptions, IValidatedOptions } from "./interfaces";

const ERRORS = {
	generic: (name: string, message?: string): Error => {
		const error = new Error(message);
		error.name = name;
		error.message = message ?? "unknown";
		return error;
	},
	missingParameter: (item: string): Error => ERRORS.generic("missingParameter", `No ${item} supplied`),
	invalidFormat: (item: string): Error => ERRORS.generic("invalidFormat", `Invalid ${item} format`),
	cannotQuitExternalClient: (): Error => ERRORS.generic("cannotQuitExternalClient", "Cannot quit external client"),
};

/**
 * Redis Tagging
 *
 * To create a new instance use:
 * 		import RedisTagging from "redis-tagging";
 * 		const rt = new RedisTagging()
 */

export default class RedisTagging {
	private redisns: string;
	private redis: ReturnType<typeof createClient>;
	private externalClient: boolean = false;

	/**
	 * Constructor of RedisTagging
	 *
	 * @param {RedisTaggingOptions} [options] object with general options for the redis tagging
	 * @param {string} [options.redisns=rt] namespace for tagging
	 * @param {number} [options.port=6379] port of redis server
	 * @param {string} [options.host=127.0.0.1] host of redis server
	 * @param {ReturnType<typeof createClient>} [options.client] redis client
	 * @param {RedisClientOptions} [options.options={}] Redis client options
	 */
	constructor(options: RedisTaggingOptions = {}) {
		this.redisns = (options.nsprefix || "rt") + ":";
		let port = options.port || 6379;
		let host = options.host || "127.0.0.1";

		if (options.client instanceof RedisClient) {
			this.redis = options.client;
			this.externalClient = true;
		} else {
			this.redis = createClient(options.options ?? { socket: { port, host }});
			this.redis.on("error", err => console.log("Redis Client Error", err));
		}
	}

	/**
	 * Quit the redis client
	 *
	 * @returns {Promise<void>}
	 */
	public quit(): Promise<void> {
		if (this.externalClient) {
			throw ERRORS.cannotQuitExternalClient();
		}
		if (this.redis.isOpen) return this.redis.quit();
		return Promise.resolve();
	}

	/**
	 * Get a list of tags for a given id in a given bucket
	 *
	 * @param {object} options options object
	 * @param {string|number} options.bucket bucket name
	 * @param {string|number} options.id id of the item
	 * @returns {Promise<string[]>}
	 */
	public async get(options: Pick<IInputOptions, "bucket" | "id">): Promise<string[]> {
		const o = this.validate(options, ["bucket", "id"]);

		let ns = this.redisns + o.bucket;

		if (!this.redis.isOpen) await this.redis.connect();

		return this.redis.sMembers(`${ns}:ID:${o.id}`);
	}

	/**
	 * Set (insert or update) an item
	 *
	 * @param {object} options options object
	 * @param {string|number} options.bucket bucket name
	 * @param {string|number} options.id id of the item
	 * @param {string[]} options.tags tags to set
	 * @param {string|number} [options.score=0] score to set
	 * @returns {Promise<true>}
	 */
	public async set(options: Pick<IInputOptions, "bucket" | "id" | "tags"> & Partial<Pick<IInputOptions, "score">>): Promise<true> {
		const o = this.validate(options, ["bucket", "id", "tags", "score"]);

		let ns = this.redisns + o.bucket;
		let id_index = `${ns}:ID:${o.id}`;

		const mc = await this.deleteID(ns, o.id);
		for (const tag of o.tags) {
			mc.push(["zincrby", ns + ":TAGCOUNT", 1, tag]);
			mc.push(["sadd", id_index, tag]);
			mc.push(["zadd", `${ns}:TAGS:${tag}`, o.score, o.id]);
		}

		if (o.tags.length) {
			mc.push(["sadd", ns + ":IDS", o.id]);
		}

		if (mc.length === 0) return true;

		if (!this.redis.isOpen) await this.redis.connect();

		const resp = await this.redis.multiExecutor(mc.map(v => ({args: v.map(n => n.toString())})));
		return true;
	}

	/**
	 * Remove an item from a bucket
	 *
	 * @param {object} options options object
	 * @param {string|number} options.bucket bucket name
	 * @param {string|number} options.id id of the item
	 * @returns {Promise<boolean>}
	 */
	public async remove(options: Pick<IInputOptions, "bucket" | "id">): Promise<boolean> {
		const o = this.validate(options, ["bucket", "id"]);
		return this.set({ ...o, tags: [] });
	}

	/**
	 * Get all IDs for a single bucket
	 *
	 * @param {object} options options object
	 * @param {string|number} options.bucket bucket name
	 * @returns {Promise<string[]>}
	 */
	public async allids(options: Pick<IInputOptions, "bucket">): Promise<string[]> {
		const o = this.validate(options, ["bucket"]);

		let ns = this.redisns + o.bucket;

		if (!this.redis.isOpen) await this.redis.connect();

		return this.redis.sMembers(ns + ":IDS");
	}

	/**
	 * Return the IDs of either a single tag or an intersection/union of two or more tags
	 *
	 * @param {object} options options object
	 * @param {string|number} options.bucket bucket name
	 * @param {string[]} options.tags tags to search
	 * @param {number} [options.limit=100] limit of results
	 * @param {string|number} [options.offset=0] offset of results list
	 * @param {string|number} [options.withscores=0] return results with scores
	 * @param {string} [options.order="asc"] order of results
	 * @param {string} [options.type="inter"] type of search
	 * @returns {Promise<object>}
	 */
	public async tags(options: Pick<IInputOptions, "bucket" | "tags"> & Partial<Pick<IInputOptions, "limit" | "offset" | "withscores" | "order" | "type">>): Promise<{
		total_items: number;
		items: string[] | {id: string; score: string}[];
		limit: number;
		offset: number;
	}> {

		const o = this.validate(options, ["bucket", "tags", "offset", "limit", "withscores", "order", "type"]);

		let rndkey, resultkey, tagsresult;
		const ns = this.redisns + o.bucket;
		const prefix = ns + ":TAGS:";

		// The last element to get
		const lastelement = o.offset + o.limit - 1;

		const mc: (string|number)[][] = [];

		// Bail if no tags supplied
		if (!o.tags.length) {
			return {
				total_items: 0,
				items: [],
				limit: o.limit,
				offset: o.offset,
			};
		}

		// intersection and union of multiple tags
		if (o.tags.length > 1) {
			rndkey =
                ns +
                new Date().getTime() +
                "_" +
                Math.floor(Math.random() * 9999999999);

			// create the redis key from the supplied tags
			const _keys = o.tags.map((tag) => prefix + tag);

			// create temporary redis key with the result
			mc.push(
				[`z${o.type}store`, rndkey, _keys.length]
					.concat(_keys)
					.concat(["AGGREGATE", "MIN"])
			);

			// if limit is 0 we don't need tu return results. Just the total_rows
			if (o.limit > 0) {
				resultkey = rndkey;
			}
		} else if (o.tags.length === 1) {
			// single tag
			mc.push(["zcard", prefix + o.tags[0]]);
			if (o.limit > 0) {
				resultkey = prefix + o.tags[0];
			}
		}

		// now run the redis query
		// get the IDs
		if (o.limit > 0) {
			tagsresult = [
				`z${o.order}range`,
				resultkey,
				o.offset,
				lastelement,
			];
			if (o.withscores) {
				tagsresult.push("WITHSCORES");
			}

			mc.push(tagsresult);
		}

		// delete the temp key if this was an intersection or union
		if (o.tags.length > 1) {
			mc.push(["del", rndkey]);
		}

		if (!this.redis.isOpen) await this.redis.connect();

		const resp = await this.redis.multiExecutor(mc.map(v => ({args: v.map(n => n.toString())})));

		let rows;
		// we don't have resp[1] is limit = 0. We just return an empty array then
		if (o.limit === 0) {
			rows = [];
		} else {
			rows = resp[1];
		}

		if (rows.length && o.withscores) {
			rows = rows.reduce((acc, curr, i, a) => {
				if (i % 2 === 0) {
					acc.push({
						id: curr,
						score: +a[i + 1],
					});
				}
				return acc;
			}, []);
		}

		return {
			total_items: resp[0] ? +resp[0] : 0,
			items: rows,
			limit: o.limit,
			offset: o.offset,
		};
	}

	/**
	 * Get the top tags for a bucket
	 *
	 * @param {object} options options object
	 * @param {string|number} options.bucket bucket name
	 * @param {string|number} [options.amount=0] amount of tags to return (0 = all)
	 * @returns {Promise<object>}
	 */
	public async toptags(options: Pick<IInputOptions, "bucket"> & Partial<Pick<IInputOptions, "amount">>): Promise<{
		total_items: number;
		items: { tag: string; count: number }[];
	}> {
		const o = this.validate(options, ["bucket", "amount"]);

		const ns = this.redisns + o.bucket;
		o.amount = o.amount - 1;
		const rediskey = ns + ":TAGCOUNT";
		const mc = [
			["zcard", rediskey],
			["zrevrange", rediskey, 0, o.amount, "WITHSCORES"],
		];

		if (!this.redis.isOpen) await this.redis.connect();

		const resp = await this.redis.multiExecutor(mc.map(v => ({
			args: v.map(n => n.toString())
		})));

		const rows = (resp[1] as string[]).reduce((acc, curr, i, a) => {
			if (i % 2 === 0) {
				acc.push({
					tag: curr,
					count: +a[i + 1],
				});
			}
			return acc;
		}, [] as {tag: string; count: number}[]);

		return {
			total_items: resp[0] ? +resp[0] : 0,
			items: rows,
		};
	}

	/**
	 * Get all buckets
	 * Use with care: Uses redis.keys
	 *
	 * @returns {Promise<string[]>}
	 */
	public async buckets(): Promise<string[]> {
		if (!this.redis.isOpen) await this.redis.connect();

		const resp = await this.redis.keys(this.redisns + "*:TAGCOUNT");
		return resp.map((v) => v.split(":")[1]);
	}

	/**
	 * Remove a bucket and all its keys
	 *
	 * @param options options object
	 * @param {string|number} options.bucket bucket name
	 * @returns {Promise<true>}
	 */
	public async removebucket(options: Pick<IInputOptions, "bucket">): Promise<true> {
		const o = this.validate(options, ["bucket"]);

		const ns = this.redisns + o.bucket;

		const mc = [
			["smembers", ns + ":IDS"],
			["zrange", ns + ":TAGCOUNT", 0, -1],
		];

		if (!this.redis.isOpen) await this.redis.connect();
		const resp = await this.redis.multiExecutor(mc.map(v => ({args: v.map(n => n.toString())})));
		const rkeys = [ns + ":IDS", ns + ":TAGCOUNT"];

		for (const e of resp[0] as string[]) {
			rkeys.push(ns + ":ID:" + e);
		}

		for (const e of resp[1] as string[]) {
			rkeys.push(ns + ":TAGS:" + e);
		}

		if (!this.redis.isOpen) await this.redis.connect();

		await this.redis.del(rkeys);

		return true;
	}

	/**
	 * Return an array with redis commands to delete an ID, all tag connections and update the counters
	 *
	 * @param ns namespace
	 * @param id id
	 * @returns {Promise<(string|number)[][]>}
	 */
	private async deleteID(ns: string, id: string): Promise<(string|number)[][]> {
		const mc: (string|number)[][] = [];
		const id_index = ns + ":ID:" + id;

		if (!this.redis.isOpen) await this.redis.connect();

		const resp = await this.redis.sMembers(id_index);
		if (resp.length) {
			for (const tag of resp) {
				mc.push(["zincrby", ns + ":TAGCOUNT", -1, tag]);
				mc.push(["zrem", `${ns}:TAGS:${tag}`, id]);
			}
			mc.push(["del", id_index]);
			mc.push(["srem", ns + ":IDS", id]);
			mc.push(["zremrangebyscore", ns + ":TAGCOUNT", 0, 0]);
		}

		return mc;
	}

	/**
	 * Validation regex for options
	 */
	private VALID: Record<string, RegExp> = { bucket: /^([a-zA-Z0-9_-]){1,80}$/ };

	/**
	 * Validate the options given to a function by the user
	 *
	 * @param options options object
	 * @param keys key to check on options object
	 * @returns validated options object
	 */
	private validate<T extends keyof IValidatedOptions>(options: Record<string, any>, keys: readonly T[]): {[K in T]: IValidatedOptions[K]} {
		const validOptions: Partial<Record<T, any>> = {};
		for (const key of keys) {
			switch (key) {
				case "bucket":
					if (!options[key])
						throw ERRORS.missingParameter(key);
					validOptions[key] = options[key].toString();
					if (!this.VALID[key].test(validOptions[key]))
						throw ERRORS.invalidFormat(key);
					break;
				case "id":
					if (!options[key])
						throw ERRORS.missingParameter(key);
					validOptions[key] = options[key].toString();
					if (!validOptions[key].length)
						throw ERRORS.missingParameter(key);
					break;
				case "tags":
					if (!options[key])
						throw ERRORS.missingParameter(key);
					if (!Array.isArray(options[key])) {
						throw ERRORS.invalidFormat(key);
					}
					validOptions[key] = options[key].map(v => v.toString());
					break;
				case "score":
					validOptions[key] = options[key] ? options[key] : 0;
					if (typeof validOptions[key] === "string")
						validOptions[key] = parseInt(options[key], 10);
					if (isNaN(validOptions[key]))
						throw ERRORS.invalidFormat(key);
					break;
				case "limit":
					if (isNaN(options[key]))
						validOptions[key] = 100;
					else validOptions[key] = Math.abs(options[key]);
					break;
				case "offset":
				case "withscores":
				case "amount":
					validOptions[key] = options[key] ? options[key] : 0;
					if (typeof validOptions[key] === "string")
						validOptions[key] = parseInt(validOptions[key], 10);
					if (isNaN(validOptions[key]))
						throw ERRORS.invalidFormat(key);
					validOptions[key] = Math.abs(validOptions[key]);
					break;
				case "order":
					validOptions[key] = options[key] === "asc" ? "" : "rev";
					break;
				case "type":
					if (options[key]?.toLowerCase() === "union")
						validOptions[key] = "union";
					else validOptions[key] = "inter";
					break;
				default:
					throw ERRORS.invalidFormat(key);
			}
		}
		return validOptions as { [K in T]: IValidatedOptions[K] };
	}
}
