# Collection Policy `when` EBNF Mini-Spec

## 1. Dokumen Terkait

- [Collection Policy Schema](collection-policy.schema.json)
- [oxBill Spec](../modules/oxbill-spec.md)
- [oxCore Spec](../modules/oxcore-spec.md)

---

## 2. Tujuan

Dokumen ini menetapkan grammar dan aturan evaluasi `when` agar implementasi parser/evaluator lintas bahasa (Gleam/TypeScript/Python/Elixir) konsisten.

Catatan: representasi payload API tetap JSON AST (sesuai schema). EBNF ini adalah **normative spec** untuk perilaku evaluator.

---

## 3. EBNF

```ebnf
when               = condition ;

condition          = group_condition | rule_condition ;

group_condition    = "{" ,
                     "\"operator\"" , ":" , logical_operator , "," ,
                     "\"conditions\"" , ":" , "[" , condition , { "," , condition } , "]" ,
                     [ "," , "\"enabled\"" , ":" , boolean ] ,
                     "}" ;

logical_operator   = "\"all\"" | "\"any\"" ;

rule_condition     = "{" ,
                     "\"field\"" , ":" , field_name , "," ,
                     "\"op\"" , ":" , compare_operator ,
                     [ "," , "\"value\"" , ":" , value ] ,
                     [ "," , "\"enabled\"" , ":" , boolean ] ,
                     "}" ;

field_name         = "\"days_past_due\""
                   | "\"invoice_status\""
                   | "\"operational_state\""
                   | "\"billing_plan\""
                   | "\"total_due_amount\""
                   | "\"is_paid\"" ;

compare_operator   = "\"eq\""
                   | "\"ne\""
                   | "\"gt\""
                   | "\"gte\""
                   | "\"lt\""
                   | "\"lte\""
                   | "\"in\""
                   | "\"not_in\""
                   | "\"between\""
                   | "\"is_true\""
                   | "\"is_false\"" ;

value              = number | string | boolean | array | between_value ;

between_value      = "{" , "\"min\"" , ":" , number , "," , "\"max\"" , ":" , number , "}" ;

array              = "[" , [ value_item , { "," , value_item } ] , "]" ;
value_item         = number | string ;

number             = json_number ;
string             = json_string ;
boolean            = "true" | "false" ;
```

---

## 4. Aturan Semantik Wajib

- Evaluasi dilakukan pada context tunggal (`days_past_due`, `invoice_status`, dst).
- Node dengan `enabled=false` diperlakukan sebagai `false` (tidak match).
- `all` = semua anak harus `true`.
- `any` = minimal satu anak `true`.
- Empty `conditions` tidak valid (harus ditolak saat validasi schema).

Operator rule:

- `eq`, `ne`: perbandingan exact type-safe.
- `gt`, `gte`, `lt`, `lte`: hanya valid untuk numeric field.
- `in`, `not_in`: `value` harus array.
- `between`: `value` harus object `{min,max}` dan `min <= max`.
- `is_true`, `is_false`: tidak menerima `value`.
- `notification_template` adalah metadata stage (opsional), tidak mempengaruhi hasil evaluasi `when`.

Field type contract:

- `days_past_due`: integer >= 0
- `invoice_status`: enum string
- `operational_state`: enum string
- `billing_plan`: enum string
- `total_due_amount`: number >= 0
- `is_paid`: boolean

---

## 5. Urutan Evaluasi Deterministik

1. Evaluasi tree `when` menghasilkan boolean `matched`.
2. Stage diproses sesuai `priority` ascending (angka kecil lebih dulu).
3. Jika stage match dan `stop_on_match=true`, evaluator berhenti.
4. Jika stage match dan `stop_on_match=false`, lanjut ke stage berikut.

Tie-breaker jika `priority` sama:

- Urutkan dengan `stage.id` ascending (lexicographic) untuk hasil stabil lintas bahasa.

---

## 6. Error Handling Normatif

Evaluator wajib mengembalikan error terstruktur:

```json
{
  "code": "INVALID_WHEN_CONDITION",
  "stage_id": "soft_throttle",
  "path": "stages[0].when.conditions[1]",
  "reason": "operator_gt_requires_numeric_field"
}
```

Kategori minimum:

- `INVALID_FIELD_TYPE`
- `INVALID_OPERATOR_FOR_FIELD`
- `MISSING_REQUIRED_VALUE`
- `INVALID_BETWEEN_RANGE`
- `UNKNOWN_FIELD`
- `UNKNOWN_OPERATOR`

---

## 7. Contoh Valid

```json
{
  "operator": "all",
  "conditions": [
    { "field": "days_past_due", "op": "gte", "value": 6 },
    { "field": "days_past_due", "op": "lte", "value": 20 },
    { "field": "is_paid", "op": "is_false" }
  ]
}
```

## 8. Contoh Invalid

```json
{
  "field": "days_past_due",
  "op": "is_true",
  "value": 10
}
```

Alasan invalid: `is_true` tidak boleh memiliki `value`.
