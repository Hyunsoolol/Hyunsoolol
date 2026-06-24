# Thesis Feedback Action Plan 260624

## 1. 교수님 피드백 요약

2026-06-24 연구미팅 후속으로 답해야 할 질문은 두 가지다.

1. vMF mixture에서 평균 방향성 모수 $\mu_k$와 집중도 모수 $\kappa_k$가 서로 어떻게 의존하는지, 그리고 $\eta_k=\kappa_k\mu_k$ 표현에서 유일성이 어떤 조건에서 성립하는지 정리한다.
2. Rossi / Separate penalty 대비 Eta-group penalty가 안 좋은 상황이 언제인지, 그 차이가 얼마나 큰지 기존 simulation과 real-data diagnostic 결과로 확인한다.

이번 문서는 새 simulation 없이 기존 문서와 summary 결과만 사용한 action plan이다.

## 2. $\mu$, $\kappa$, $\eta$ 의존성과 유일성

vMF component density는 다음과 같다.

$$
f(x\mid \mu_k,\kappa_k)=C_d(\kappa_k)\exp(\kappa_k\mu_k^\top x),
\qquad \|\mu_k\|_2=1,\quad \kappa_k\ge 0.
$$

Posterior decision score에는 $\mu_k$ 단독이 아니라

$$
\eta_k=\kappa_k\mu_k
$$

가 직접 들어간다.

$$
\log \alpha_k+\log C_d(\|\eta_k\|_2)+\eta_k^\top x_i.
$$

따라서 $\mu_k$와 $\kappa_k$는 최적화와 해석에서 분리된 모수가 아니다. $\mu_k$는 방향을, $\kappa_k$는 그 방향의 decision strength를 정하지만, 실제 선형 decision term은 두 모수의 곱인 $\eta_k$다.

Parameterization-level uniqueness는 다음처럼 정리할 수 있다. $\eta_k\ne 0$이면

$$
\kappa_k=\|\eta_k\|_2,\qquad
\mu_k=\eta_k/\|\eta_k\|_2
$$

로 $\mu_k$와 $\kappa_k$를 유일하게 복원할 수 있다. 즉 단일 vMF component 수준에서는 $\kappa_k>0$ 조건 아래 $(\mu_k,\kappa_k)$와 $\eta_k$ 표현이 one-to-one이다.

주의할 점은 다음과 같다.

- $\eta_k=0$ 또는 $\kappa_k=0$이면 vMF density가 균일분포에 가까워지고 $\mu_k$ 방향은 식별되지 않는다.
- mixture model에서는 component label switching이 남아 있다.
- near-empty component, component collapse, 매우 약한 concentration에서는 수치적으로 안정적인 유일성 주장을 하기 어렵다.
- 따라서 논문에서는 전역 식별성 증명처럼 쓰지 말고, **$\kappa_k>0$에서의 parameterization-level uniqueness**라고 표현하는 것이 안전하다.

추정 알고리즘 관점에서는 unpenalized vMF M-step candidate를 만들 때 mean resultant vector에서 $\mu_k^0$와 $\kappa_k^0$ 후보가 함께 나온다. 이후 Eta-group proximal step은 $\eta_k$를 shrink한 뒤 $\kappa_k=\|\eta_k\|_2$, $\mu_k=\eta_k/\|\eta_k\|_2$로 복원한다. 그러므로 초기 또는 후보 생성에는 concentration approximation이 들어가지만, shrink 이후의 $\mu,\kappa$ 복원은 추정된 $\eta$의 norm과 direction으로 결정된다.

## 3. 기존 결과 기준 Eta-group이 좋은 상황

| Setting | Evidence | Interpretation |
|:---|:---|:---|
| K=2 toy | 모든 방법 ARI=1.000. Eta-group + refit selected q=13.20, FPR=0.036 vs Rossi/Separate selected q=23.30, FPR=0.148. | clustering이 쉬운 상황에서 Eta contrast penalty가 support를 더 sparse하게 만든다. |
| K=4 strong common+specific | Eta-group + refit ARI=0.686, selected q=24.75, FPR=0.037, Precision=0.890, F1=0.937. Rossi BIC는 ARI=0.680이지만 selected q=98.52, FPR=0.981. | 현재 main evidence. Eta-group의 장점은 ARI 대폭 개선이 아니라 ARI 유지와 support recovery 개선이다. |
| Weak d=100 | Eta-group + refit ARI=0.575, selected q=24.09, FPR=0.027, F1=0.956. Rossi/Separate는 selected q가 거의 100이고 FPR이 거의 1. | robustness evidence로는 양호하다. |
| d=200 long path + adaptive diagnostic | selected q=40.98, FPR=0.127, Precision=0.741, F1=0.715. | high-dimensional 보강 후보로는 의미가 있지만 official algorithm은 아니다. |
| SPLADE BBC3 d=500 EBIC | Eta-group + refit ARI=0.911, selected q=206 vs Rossi EBIC ARI=0.903, selected q=489. | real-data diagnostic 후보. SPLADE token-level support 해석 가능성이 있다. |

## 4. 기존 결과 기준 Eta-group이 안 좋은 상황

| Setting | Compared methods | Metric where Eta-group is worse | Eta-group value | Rossi/Separate value | Difference | Likely reason | Severity | What to say in paper |
|:---|:---|:---|---:|---:|---:|:---|:---|:---|
| K=4 strong, penalized fit before refit | Eta BIC vs Rossi/Separate BIC | ARI | 0.625 | Rossi 0.680 / Separate 0.684 | -0.055 / -0.059 | penalty shrinkage can hurt clustering before refit | Minor | Refit is essential; do not report penalized fit alone as final. |
| K=4 signal $w=0.35$ | Eta + refit vs Separate BIC | ARI | 0.505 | Separate 0.528 | -0.023 | weaker component-specific signal makes support shrinkage trade off against clustering | Minor to moderate | Eta improves support but can lose some ARI under weaker signal. |
| K=4 signal $w=0.25$ | Eta + refit vs Separate BIC | ARI and $\kappa$ MSE | ARI 0.399, MSE_kappa about $4.999\times 10^9$ | Separate ARI 0.401, MSE_kappa 60.743 | ARI -0.002, huge $\kappa$ instability | very weak signal / local instability / concentration blow-up | Serious for parameter estimation | Need numerical stability and negative-control discussion; avoid claiming uniformly stable $\kappa$ estimation. |
| d=200 basic path | Eta + refit absolute performance | selected q, FPR | selected q=120.06, FPR=0.552 | true q=22 target | +98.06 q over target | basic path lacks sparse candidate support | Moderate | Better than dense baselines but not successful sparse recovery. |
| d=400 basic path | Eta + refit absolute performance | selected q, FPR, F1 | selected q=262.95, FPR=0.642, F1=0.146 | true q=22 target | severe over-selection | high-dimensional path/tuning failure | Serious | Treat as limitation, not success. |
| d=400 path+adaptive diagnostic | adaptive vs official long path | ARI, selected q, FPR, F1 | ARI=0.155, selected q=308.00, FPR=0.760, F1=0.127 | long path Eta + refit ARI=0.238, selected q=68.75, FPR=0.146, F1=0.441 | worse on all key metrics | adaptive weights unstable in d=400 stress | Serious | Adaptive penalty is not official; keep as failed diagnostic in appendix. |
| SPLADE BBC5 top500 | Eta vs Rossi | ARI and sparsity | Eta + refit EBIC ARI=0.817, selected q=500 | Rossi EBIC ARI=0.857, selected q=500 | ARI -0.040, no sparsity gain | five-class benchmark is harder; BIC/EBIC/RICc all choose dense support | Serious for real data | BBC5 is not a main positive result. |
| SPLADE 20NG4 top300 | Eta EBIC/RICc vs Rossi EBIC | ARI | Eta EBIC + refit ARI=0.461, q=125; Eta RICc + refit ARI=0.450, q=81 | Rossi EBIC ARI=0.715, q=300 | ARI -0.254 to -0.265 | sparse support causes cluster degradation on overlapping topics | Serious | Standard benchmark diagnostic shows sparsity-clustering tradeoff. |
| TF-IDF BBC3 matched top500 | Eta EBIC + refit | ARI | 0.344, selected q=101 | SPLADE Eta EBIC + refit ARI=0.911, q=206 | -0.567 vs SPLADE representation | representation quality matters; sparse coordinates alone are insufficient | Diagnostic only | Real-data claim should be representation-specific. |

## 5. Rossi/Separate 대비 차이 정량 요약

요약하면 Eta-group이 Rossi/Separate보다 항상 좋은 것은 아니다.

- ARI 기준: strong setting에서는 refit 후 Eta-group이 가장 높거나 비슷하지만, $w=0.35$에서는 Separate BIC보다 ARI가 약 0.023 낮다. $w=0.25$에서는 Separate BIC와 거의 같지만 $\kappa$ MSE가 매우 불안정하다.
- Support 기준: d=100 strong/weak에서는 Eta-group이 Rossi/Separate보다 훨씬 좋다. Rossi/Separate는 selected q가 거의 전체 차원에 가까운 경우가 많다.
- Parameter estimation 기준: strong/weak에서는 Eta-group + refit의 MSE_centered_eta와 MSE_kappa가 좋아지는 편이다. 그러나 $w=0.25$에서는 Eta-group의 $\kappa$ MSE가 폭발한다.
- High-dimensional 기준: d=200/d=400에서는 Eta-group이 Rossi/Separate보다 덜 dense하지만 true q=22 근처 회복에는 실패한다.
- Real-data 기준: BBC3는 긍정적이지만, BBC5와 20NG4에서는 Eta-group이 Rossi보다 ARI가 낮거나 sparse tuning에서 clustering이 크게 무너진다.

## 6. 논문에 안전하게 쓸 수 있는 표현

- Eta-group은 ARI를 항상 높이는 방법이 아니라, vMF mixture의 posterior decision parameter $\eta=\kappa\mu$에 기반한 sparse coordinate support recovery를 목표로 한다.
- $\kappa_k>0$이면 $\eta_k$에서 $\mu_k$와 $\kappa_k$를 $\kappa_k=\|\eta_k\|_2$, $\mu_k=\eta_k/\|\eta_k\|_2$로 복원할 수 있다.
- 이 유일성은 parameterization-level statement이며, mixture label switching과 degeneracy 문제는 별도로 남는다.
- Strong d=100 setting에서는 Eta-group + refit이 clustering을 유지하면서 selected q와 FPR을 크게 줄인다.
- Weak d=100 setting은 robustness evidence로 볼 수 있지만 main claim은 strong common+specific setting에 두는 것이 안전하다.
- High-dimensional d=200/d=400 결과는 limitation과 path construction 문제로 제시한다.
- BBC3 SPLADE 결과는 appendix/diagnostic real-data 후보로 둔다.

## 7. 주장하면 위험한 표현

- Eta-group이 항상 Rossi/Separate보다 좋다.
- Eta-group이 ARI를 보편적으로 개선한다.
- $\eta$ parameterization이 mixture model의 전역 식별성 증명을 제공한다.
- proximal EM-type update가 정확한 EM 알고리즘이다.
- line-search가 전역 최적해 또는 전역 수렴을 보장한다.
- path+BIC가 high-dimensional sparse recovery를 안정적으로 해결한다.
- adaptive penalty가 official algorithm이다.
- SPLADE BBC3가 최종 real-data 검증이다.

## 8. 추가로 필요한 simulation / diagnostic

새 simulation은 바로 실행하기보다 다음 순서로 설계하는 것이 좋다.

1. Dense true eta contrast negative control: 실제 active coordinate가 많을 때 Eta-group이 과도한 sparsity로 손해를 보는지 확인한다.
2. Weak signal / low concentration stress: $w=0.25$의 $\kappa$ instability를 재현하고 원인을 분해한다.
3. Rossi/Separate favorable setting: component 간 차이가 주로 $\mu$ direction sparsity로 설명되고 concentration contrast가 약한 setting을 설계한다.
4. High-dimensional path construction: d=200/d=400에서 near-true q 후보가 path에 충분히 생기도록 path range/density를 비교한다.
5. Tuning criterion comparison: BIC, EBIC, RIC-like, stability/positive-support criteria를 같은 candidate path 위에서 비교한다.
6. Real-data benchmark: BBC3는 diagnostic positive example, BBC5/20NG4는 negative or stress benchmark로 분리한다.

## 9. 우선순위별 TODO

| Priority | Task | Reason | Output |
|:---|:---|:---|:---|
| P0 | $\mu,\kappa,\eta$ 의존성과 유일성 문단을 methods note에 반영 | 교수님 첫 번째 피드백에 직접 답변 | Methods subsection |
| P0 | Eta-group이 안 좋은 상황 표를 simulation note에 추가 | 교수님 두 번째 피드백에 직접 답변 | Negative evidence table |
| P1 | $w=0.25$ $\kappa$ blow-up 원인 점검 | parameter estimation reviewer risk | diagnostic note |
| P1 | high-dimensional failure 원인을 path candidate 부족 vs penalty 구조로 분리 | d=200/d=400 limitation 방어 | appendix diagnostic |
| P2 | Rossi/Separate favorable negative-control simulation 설계 | 제안 방법의 적용 범위 명확화 | simulation design |
| P2 | BBC5/20NG4를 real-data stress 결과로 정리 | BBC3만 골라 썼다는 비판 방지 | real-data appendix |
| P3 | journal-facing claim을 낮춘 Introduction/Discussion 작성 | 투고 리스크 감소 | manuscript draft |

## 10. 다음 답변 초안

교수님께는 다음처럼 답하는 것이 가장 안전하다.

> $\eta_k=\kappa_k\mu_k$ 표현은 $\kappa_k>0$이면 $\kappa_k=\|\eta_k\|_2$, $\mu_k=\eta_k/\|\eta_k\|_2$로 유일하게 복원됩니다. 다만 mixture label switching, $\kappa_k=0$, near-empty component에서는 식별성 주장을 조심해야 하므로 전역 식별성 증명이 아니라 parameterization-level uniqueness로 정리하겠습니다.

> Eta-group은 strong/weak d=100에서는 Rossi/Separate보다 support recovery가 좋지만, 항상 좋은 것은 아닙니다. 약한 signal에서는 ARI가 Separate보다 약간 낮거나 $\kappa$ MSE가 불안정하고, high-dimensional d=400이나 BBC5/20NG4 real-data benchmark에서는 dense support 또는 ARI 하락이 나타납니다. 이 부분을 negative evidence와 limitation으로 정리하고, Rossi/Separate가 유리한 setting을 의도적으로 설계해 추가 확인하겠습니다.
