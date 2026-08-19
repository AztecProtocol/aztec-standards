//! Overflow-safe fixed-point conversion math for the vault.
//!
//! The share<>asset conversions compute `a * b / denominator`. Done natively in `u128`, the
//! intermediate product `a * b` overflows for large-but-legitimate inputs (Noir range-checks u128,
//! so the transaction reverts rather than wrapping) — this is the availability bug flagged by the
//! 2026-08 security audit (F-004). We compute the product and the division in a 256-bit intermediate
//! (`noir-bignum`'s `U256` — three 120-bit limbs, modulus 2^256) so nothing overflows until
//! the final result, which is narrowed back to `u128` and only fails if the true result genuinely
//! exceeds `u128` — an impossibility for real balances.

use bignum::bignum::BigNum;
use bignum::U256;

/// 2^120, the width of a single `U256` limb. A `u128` splits across the low two limbs: limb 0 holds
/// the low 120 bits, limb 1 the high 8 bits.
global TWO_POW_120: u128 = 0x1000000000000000000000000000000;

/// Widens a `u128` into a `U256` (little-endian, 120-bit limbs).
fn u256_from_u128(v: u128) -> U256 {
    U256::from_limbs([v % TWO_POW_120, v / TWO_POW_120, 0])
}

/// Narrows a `U256` back to `u128`, asserting it fits. Reverts if the value exceeds `u128::MAX`.
fn u256_to_u128(v: U256) -> u128 {
    let hi = v.get_limb(1);
    // A u128 occupies limb 0 (120 bits) plus at most the low 8 bits of limb 1; anything above that
    // does not fit. `hi < 256` keeps `hi * TWO_POW_120` below 2^128 so the reconstruction cannot
    // itself overflow.
    assert((v.get_limb(2) == 0) & (hi < 256), "conversion result exceeds u128");
    // hi < 256 (asserted above), so hi * TWO_POW_120 < 2^128 and the sum fits u128.
    v.get_limb(0) + hi * TWO_POW_120
}

/// True iff `v` is zero.
fn u256_is_zero(v: U256) -> bool {
    (v.get_limb(0) == 0) & (v.get_limb(1) == 0) & (v.get_limb(2) == 0)
}

/// Computes `a * b / denominator` without overflowing on the intermediate product.
///
/// Rounds down by default; when `round_up` is true and the division leaves a remainder, rounds up.
/// This matches the previous native-`u128` implementation exactly for every input that did not
/// overflow — the widening only extends the range of inputs that succeed, it does not change any
/// result. `denominator` must be non-zero (it always is at the call sites: `total_assets + 1` and
/// `total_supply + vault_offset` with `vault_offset >= 1`).
pub fn mul_div(a: u128, b: u128, denominator: u128, round_up: bool) -> u128 {
    // noir-bignum's constrained `udiv_mod` enforces `remainder < divisor` (which fails for a zero
    // divisor), but its unconstrained path assumes a non-zero divisor and would otherwise return a
    // meaningless witness. Guard explicitly so the helper is safe in isolation, not only at the
    // vault's (always non-zero) call sites.
    assert(denominator > 0, "division by zero");
    let numerator = u256_from_u128(a) * u256_from_u128(b);
    let (quotient, remainder) = numerator.udiv_mod(u256_from_u128(denominator));

    let mut result = u256_to_u128(quotient);
    if round_up & !u256_is_zero(remainder) {
        result = result + 1;
    }
    result
}

mod test {
    use super::{mul_div, TWO_POW_120, u256_from_u128, u256_to_u128};

    global ROUND_DOWN: bool = false;
    global ROUND_UP: bool = true;

    #[test]
    fn round_trip_u128_boundaries() {
        // The widen/narrow pair is identity across the u128 range.
        for v in [0, 1, TWO_POW_120 - 1, TWO_POW_120, 0xffffffffffffffffffffffffffffffff] {
            assert_eq(u256_to_u128(u256_from_u128(v)), v);
        }
    }

    #[test]
    fn matches_native_for_small_values() {
        // Exact division: no rounding either way.
        assert_eq(mul_div(1000, 3, 3, ROUND_DOWN), 1000);
        assert_eq(mul_div(1000, 3, 3, ROUND_UP), 1000);
        // 1:1 ratio, the vault's initial state.
        assert_eq(mul_div(1000, 1, 1, ROUND_DOWN), 1000);
        // Zero numerator.
        assert_eq(mul_div(0, 12345, 7, ROUND_UP), 0);
    }

    #[test]
    fn rounding_direction_is_preserved() {
        // 7 / 2 = 3 remainder 1: down floors, up ceils. This is the invariant the vault's economic
        // safety depends on — rounding must never shift, or value leaks to or from depositors.
        assert_eq(mul_div(7, 1, 2, ROUND_DOWN), 3);
        assert_eq(mul_div(7, 1, 2, ROUND_UP), 4);
        // 10 / 3 = 3 remainder 1.
        assert_eq(mul_div(5, 2, 3, ROUND_DOWN), 3);
        assert_eq(mul_div(5, 2, 3, ROUND_UP), 4);
        // No remainder => up does NOT add one.
        assert_eq(mul_div(9, 1, 3, ROUND_UP), 3);
    }

    #[test]
    fn product_that_overflowed_u128_now_converts() {
        // a * b here is 2^200, far beyond u128::MAX (2^128 - 1); the native `a * b` reverted.
        // 2^100 * 2^100 / 2^100 = 2^100, which fits u128.
        let two_pow_100: u128 = 0x10000000000000000000000000;
        assert_eq(mul_div(two_pow_100, two_pow_100, two_pow_100, ROUND_DOWN), two_pow_100);

        // A non-trivial ratio at the same scale: (2^100 * (3 * 2^100)) / (2 * 2^100) = 3 * 2^100 / 2
        // = 1.5 * 2^100 => floor is 2^100 + 2^99, ceil the same (exact, no remainder).
        let expected: u128 = two_pow_100 + (two_pow_100 / 2);
        assert_eq(mul_div(two_pow_100, 3 * two_pow_100, 2 * two_pow_100, ROUND_DOWN), expected);
        assert_eq(mul_div(two_pow_100, 3 * two_pow_100, 2 * two_pow_100, ROUND_UP), expected);
    }

    #[test]
    fn max_operands_do_not_overflow_the_intermediate() {
        // Both operands at u128::MAX: native `a * b` = (2^128-1)^2 reverts; here it divides cleanly.
        let max: u128 = 0xffffffffffffffffffffffffffffffff;
        // max * max / max = max.
        assert_eq(mul_div(max, max, max, ROUND_DOWN), max);
    }

    #[test(should_fail_with = "division by zero")]
    fn zero_denominator_reverts() {
        // The helper guards a zero denominator explicitly (unreachable from the vault, whose
        // denominators are total_assets+1 / total_supply+vault_offset with vault_offset >= 1).
        let _ = mul_div(100, 5, 0, ROUND_DOWN);
    }

    #[test(should_fail_with = "conversion result exceeds u128")]
    fn result_exceeding_u128_reverts_cleanly() {
        // max * max / 1 = (2^128-1)^2, which genuinely does not fit u128. Reverts with our message
        // rather than a raw range-check failure. Unreachable for real balances (would require a
        // denominator far below the operands), but proves the narrowing guard is present.
        let max: u128 = 0xffffffffffffffffffffffffffffffff;
        let _ = mul_div(max, max, 1, ROUND_DOWN);
    }
}
