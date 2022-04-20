import { createClient, RedisClientOptions } from "redis";

export interface RedisTaggingOptions {
	nsprefix?: string;
	port?: number;
	host?: string;
	options?: RedisClientOptions;
	client?: ReturnType<typeof createClient>;
}

export type IInputOptions = {
	bucket: string | number;
	id: string | number;
	tags: (string | number)[];
	score: string | number;
	limit: number;
	offset: string | number;
	withscores: string | number;
	amount: string | number;
	order: "asc" | "desc";
	type: "union" | "inter";
};

export type IValidatedOptions = {
	bucket: string;
	id: string;
	tags: string[];
	score: number;
	limit: number;
	withscores: number;
	amount: number;
	offset: number;
	type: "union" | "inter";
	order: "asc" | "rev";
};