# Artifact inválido: prompt-temperature experiment e4b

Los artifacts [JSON](2026-08-23-prompt-temperature-experiment-e4b.json) y [HTML](2026-08-23-prompt-temperature-experiment-e4b.html) de la corrida anterior quedan invalidados por una violación del control experimental.

`freeze_retrieval` construía `RAGService` con `HybridIndex`, por lo que se aplicaba el gate global productivo y no el filtro individual por chunk `max(answer,q1,q2) >= 0.50`, preservando chunks que la variante per-chunk debía filtrar.

La corrida corregida, ejecutada desde cero, está en [JSON](2026-08-23-prompt-temperature-experiment-e4b-per-chunk-050.json) y [HTML](2026-08-23-prompt-temperature-experiment-e4b-per-chunk-050.html).
