"""Fallback sort ordering for GGUF quant types.

Sort key components:
  sb  = same/different BPW (0 same, 1 different)
  ss  = same base type (0 same, 1 different)
  sv  = variant relationship
  sk  = scale factor (larger = better, but inverted for sort)
  ir  = import/legacy (0 = import (I-prefix), 1 = legacy)
  sg  = sub-guard (1 if _Rn variant)
  sr2 = sub-guard rank (1 for _R4, 2 for _R8)
"""
import sys
import argparse

bpw = {
    'F32': 32, 'F16': 16, 'BF16': 16,
    'Q8_0_R8': 8.5, 'Q8_0': 8.5, 'Q8_K_R8': 8.0625, 'Q8_KV': 8, 'F8': 8,
    'IQ6_K': 6.625,
    'Q6_K_R4': 6.5625, 'Q6_K': 6.5625, 'Q6_0_R4': 6.5, 'Q6_0': 6.5,
    'Q5_1': 6,
    'Q5_K_R4': 5.5, 'Q5_K': 5.5, 'Q5_0_R4': 5.5, 'Q5_0': 5.5,
    'IQ5_K_R4': 5.5, 'IQ5_K': 5.5, 'IQ5_KS_R4': 5.25, 'IQ5_KS': 5.25,
    'Q4_1': 5,
    'Q4_K_R4': 4.5, 'Q4_K': 4.5, 'Q4_0_R8': 4.5, 'Q4_0': 4.5,
    'IQ4_NL_R4': 4.5, 'IQ4_NL': 4.5, 'IQ4_K_R4': 4.5, 'IQ4_K': 4.5,
    'IQ4_XS_R8': 4.25, 'IQ4_XS': 4.25, 'IQ4_KS_R4': 4.25, 'IQ4_KS': 4.25,
    'IQ4_KT': 4, 'IQ4_KSS': 4, 'IQ3_KL': 4,
    'IQ3_M': 3.66,
    'Q3_K_R4': 3.4375, 'Q3_K': 3.4375, 'IQ3_S_R4': 3.4375, 'IQ3_S': 3.4375,
    'IQ3_K_R4': 3.4375, 'IQ3_K': 3.4375,
    'IQ3_XS': 3.3, 'IQ3_KS': 3.1875, 'IQ3_KT': 3.125,
    'IQ3_XXS_R4': 3.0625, 'IQ3_XXS': 3.0625,
    'IQ2_M_R4': 2.7, 'IQ2_M': 2.7,
    'IQ2_KL': 2.6875,
    'Q2_K_R4': 2.625, 'Q2_K': 2.625, 'IQ2_S': 2.5625,
    'IQ2_K_R4': 2.375, 'IQ2_K': 2.375, 'IQ2_XS_R4': 2.3125, 'IQ2_XS': 2.3125,
    'IQ2_KS': 2.1875, 'IQ2_KT': 2.125,
    'IQ2_XXS_R4': 2.0625, 'IQ2_XXS': 2.0625,
    'IQ2_BN_R4': 2, 'IQ2_BN': 2,
    'IQ1_M_R4': 1.75, 'IQ1_M': 1.75, 'IQ1_KT': 1.75,
    'IQ1_BN': 1.625, 'IQ1_S': 1.5625, 'IQ1_S_R4': 1.5,
}

scale = {
    'IQ1_BN': 2, 'IQ1_KT': 4,
    'IQ2_BN': 4, 'IQ2_BN_R4': 4, 'IQ2_KL': 2, 'IQ2_KS': 2, 'IQ2_KT': 4,
    'IQ3_KS': 2, 'IQ3_KT': 4,
    'IQ4_KS': 4, 'IQ4_KSS': 4, 'IQ4_KS_R4': 4, 'IQ4_KT': 4,
    'IQ5_KS': 4, 'IQ5_KS_R4': 4,
    'Q8_KV': 8, 'IQ1_S_R4': 2, 'IQ1_M_R4': 2, 'Q8_KV_R8': 4,
}


def qbase(q):
    if q.endswith('_R4') or q.endswith('_R8'):
        return q[:q.rfind('_')]
    return q


def variant_rank(q):
    if q.endswith('_R4'):
        return 1
    if q.endswith('_R8'):
        return 2
    return 0


def sort_fallbacks(current, fallbacks, chain=False):
    current = current.upper()
    cBPW = bpw.get(current)
    if cBPW is None:
        print(f"Error: unknown qtype '{current}'")
        sys.exit(2)

    cBase = qbase(current)
    cVar = variant_rank(current) > 0

    candidates = []
    for fb in fallbacks:
        fb = fb.upper().strip()
        if not fb or fb == 'BF16' or fb == current:
            continue
        if fb not in bpw:
            continue
        fbBPW = bpw[fb]
        if fbBPW < cBPW:
            continue

        fbBase = qbase(fb)
        fbVar = variant_rank(fb) > 0
        sb = 0 if fbBPW == cBPW else 1

        ss = 1
        sv = 0
        if fbBase == cBase:
            ss = 0
            if cVar:
                if not fbVar:
                    sv = 0
                else:
                    sv = 1 + variant_rank(fb)
            else:
                if fbVar:
                    sv = variant_rank(fb)
                else:
                    sv = 99

        sk = scale.get(fb, 0)
        ir = 0 if fb.startswith('I') else 1
        sg = 1 if fbVar else 0
        sr2 = variant_rank(fb)

        key = '|'.join(str(x) for x in [sb, ss, sv, sk, ir, sg, sr2, fb])
        candidates.append((key, fb, fbBPW))

    sorted_cands = sorted(candidates, key=lambda x: x[0])

    if chain:
        print(f"Current: {current} (BPW={cBPW})")
        print("Ordered eligible fallbacks:")
        for i, (_, q, b) in enumerate(sorted_cands, 1):
            print(f"  {i}. {q} (BPW={b})")
    else:
        if sorted_cands:
            print(sorted_cands[0][1])
        else:
            print("No eligible fallback found.")


def main():
    parser = argparse.ArgumentParser(description='Find next fallback qtype')
    parser.add_argument('--current', required=True, help='The qtype that just failed')
    parser.add_argument('--fallbacks', required=True, nargs='+', help='Fallback pool')
    parser.add_argument('--chain', action='store_true', help='Print full chain')
    args = parser.parse_args()
    sort_fallbacks(args.current, args.fallbacks, args.chain)


if __name__ == '__main__':
    main()
