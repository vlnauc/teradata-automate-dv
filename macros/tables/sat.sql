{%- macro sat(src_pk, src_hashdiff, src_payload, src_eff, src_ldts, src_source, source_model) -%}

    {{- adapter.dispatch('sat', packages = dbtvault.get_dbtvault_namespaces())(src_pk=src_pk, src_hashdiff=src_hashdiff,
                                                                               src_payload=src_payload, src_eff=src_eff, src_ldts=src_ldts,
                                                                               src_source=src_source, source_model=source_model) -}}

{%- endmacro %}

{%- macro default__sat(src_pk, src_hashdiff, src_payload, src_eff, src_ldts, src_source, source_model) -%}

{{- dbtvault.check_required_parameters(src_pk=src_pk, src_hashdiff=src_hashdiff, src_payload=src_payload,
                                       src_eff=src_eff, src_ldts=src_ldts, src_source=src_source,
                                       source_model=source_model) -}}

{%- set source_cols = dbtvault.expand_column_list(columns=[src_pk, src_hashdiff, src_payload, src_eff, src_ldts, src_source]) -%}
{%- set rank_cols = dbtvault.expand_column_list(columns=[src_pk, src_hashdiff, src_ldts]) -%}
{%- set pk_cols = dbtvault.expand_column_list(columns=[src_pk]) -%}

{%- if model.config.materialized == 'vault_insert_by_rank' %}
    {%- set source_cols_with_rank = source_cols + [config.get('rank_column')] -%}
{%- endif -%}

{{ dbtvault.prepend_generated_by() }}

WITH source_data AS (
    {%- if model.config.materialized == 'vault_insert_by_rank' %}
    SELECT {{ dbtvault.prefix(source_cols_with_rank, 'a', alias_target='source') }}
    {%- else %}
    SELECT {{ dbtvault.prefix(source_cols, 'a', alias_target='source') }}
    {%- endif %}
    FROM {{ ref(source_model) }} AS a
    WHERE {{ dbtvault.prefix([src_pk], 'a') }} IS NOT NULL
    {%- if model.config.materialized == 'vault_insert_by_period' %}
    AND __PERIOD_FILTER__
    {% elif model.config.materialized == 'vault_insert_by_rank' %}
    AND __RANK_FILTER__
    {% endif %}
),

{% if dbtvault.is_any_incremental() %}

latest_records AS (

    SELECT {{ dbtvault.prefix(rank_cols, 'current_records', alias_target='target') }},
           RANK() OVER (
               PARTITION BY {{ dbtvault.prefix([src_pk], 'current_records') }}
               ORDER BY {{ dbtvault.prefix([src_ldts], 'current_records') }} DESC
           ) AS rank
    FROM {{ this }} AS current_records
    JOIN (
        SELECT DISTINCT {{ dbtvault.prefix([src_pk], 'source_data') }}
        FROM source_data
    ) AS source_records
    ON {{ dbtvault.prefix([src_pk], 'current_records') }} = {{ dbtvault.prefix([src_pk], 'source_records') }}
    QUALIFY rank = 1
),
{%- endif %}

records_to_insert AS (
    SELECT DISTINCT {{ dbtvault.alias_all(source_cols, 'stage') }}
    FROM source_data AS stage
    {%- if dbtvault.is_any_incremental() %}
    LEFT JOIN latest_records
    ON {{ dbtvault.prefix([src_pk], 'latest_records', alias_target='target') }} = {{ dbtvault.prefix([src_pk], 'stage') }}
    WHERE {{ dbtvault.prefix([src_hashdiff], 'latest_records', alias_target='target') }} != {{ dbtvault.prefix([src_hashdiff], 'stage') }}
        OR {{ dbtvault.prefix([src_hashdiff], 'latest_records', alias_target='target') }} IS NULL
    {%- endif %}
)

SELECT * FROM records_to_insert

{%- endmacro -%}