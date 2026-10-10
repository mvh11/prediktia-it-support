# Statistics catch-up — production backlog measurement

Chief-authorized SELECT-only measurement using the production read-only reader.

- BACKLOG_MEASUREMENT: PASS
- READ_ONLY_READER_USED: YES
- PROVIDER_REQUESTS: 0
- PRODUCTION_WRITES: 0
- TOTAL_FIXTURES: 18671
- STATISTICS_COVERED_FIXTURES: 12064
- STATISTICS_MISSING_FIXTURES: 6607
- BACKLOG_FIXTURES: 6607
- ACTIVE_RUNS: 0
- BATCH_SIZE: 20
- ESTIMATED_REQUEST_BATCHES: 331
- REQUEST_ESTIMATE: REQUIRES_PROVIDER/EXECUTION_SEMANTICS
- DATA_QUALITY_OR_AMBIGUITY: NONE
- READY_FOR_CATCHUP_PLANNING: YES
- BLOCKERS: NONE

Statistics run-state counts:
- completed: 39
- completed_with_errors: 1
- dry_run_completed: 35

Backlog by season (aggregate counts only):
- 189: 507
- 214: 481
- 230: 384
- 59: 380
- 93: 380
- 127: 380
- 42: 378
- 174: 312
- 25: 306
- 76: 306
- 110: 306
- 263: 306
- 252: 305
- 286: 239
- 143: 234
- 202: 224
- 159: 207
- 272: 176
- 302: 156
- 294: 154
- 241: 153
- 308: 108
- 277: 104
- 5: 51
- 219: 32
- 8: 16
- 251: 10
- 187: 4
- 229: 3
- 271: 2
- 24: 1
- 158: 1
- 173: 1

No provider call, production write, scheduler/job invocation, or catch-up execution was performed.