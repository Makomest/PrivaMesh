/**
 * Generate the RSA issuer keypair for anonymous blind tokens.
 * Run:  npm run keygen           (from relay/)
 *
 * Prints the three env values. N and E are public; D is the signing SECRET —
 * set it with `wrangler secret put TOKEN_RSA_D` and NEVER commit it. Rotating
 * the key invalidates all outstanding tokens (clients simply re-issue).
 */
import { generateKeyPairSync } from 'node:crypto';

const bits = parseInt(process.argv[2] ?? '2048', 10);
if (!Number.isFinite(bits) || bits < 2048) {
  console.error(`refusing to generate a ${bits}-bit key: minimum is 2048-bit.`);
  process.exit(1);
}
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: bits });
const jwk = privateKey.export({ format: 'jwk' }); // n, e, d already base64url

console.log(`# RSA-${bits} blind-token issuer key\n`);
console.log(`# public exponent (put in wrangler.toml [vars], or as a secret):`);
console.log(`TOKEN_RSA_E=${jwk.e}\n`);
console.log(`# public modulus — set as a secret:  wrangler secret put TOKEN_RSA_N`);
console.log(`TOKEN_RSA_N=${jwk.n}\n`);
console.log(`# SIGNING SECRET — set as a secret:  wrangler secret put TOKEN_RSA_D`);
console.log(`# never commit this value.`);
console.log(`TOKEN_RSA_D=${jwk.d}`);
