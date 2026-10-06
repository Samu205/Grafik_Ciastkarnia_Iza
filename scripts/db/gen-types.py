#!/usr/bin/env python3
"""Generuje lib/types/database.ts z lokalnej bazy PostgreSQL w formacie `supabase gen types`.

Zapasowe narzędzie na wypadek braku Supabase CLI. Gdy CLI działa, używaj:
    supabase gen types typescript --local > lib/types/database.ts

Użycie (po scripts/db/test-local.sh, które tworzy bazę grafik_test):
    TEST_DB_NAME=grafik_test python3 scripts/db/gen-types.py > lib/types/database.ts
Połączenie przez standardowe zmienne PGHOST, PGPORT, PGUSER.
"""

import os
import subprocess
import sys
from collections import defaultdict

DB = os.environ.get("TEST_DB_NAME", "grafik_test")
SEP = "\x1f"


def query(sql: str) -> list[list[str]]:
    out = subprocess.run(
        ["psql", "-X", "-q", "-t", "-A", "-F", SEP, "-d", DB, "-c", sql],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [line.split(SEP) for line in out.splitlines() if line]


enums: dict[str, list[str]] = defaultdict(list)
for name, label in query(
    """
    select t.typname, e.enumlabel
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
    order by t.typname, e.enumsortorder
    """
):
    enums[name].append(label)


def ts_type(pg_type: str) -> str:
    base = pg_type.removesuffix("[]")
    is_array = pg_type.endswith("[]")
    if base in enums:
        t = f'Database["public"]["Enums"]["{base}"]'
    elif base in ("uuid", "text", "date", "time without time zone", "timestamp with time zone",
                  "timestamp without time zone", "character varying", "interval"):
        t = "string"
    elif base in ("integer", "bigint", "smallint", "numeric", "real", "double precision"):
        t = "number"
    elif base == "boolean":
        t = "boolean"
    elif base in ("jsonb", "json"):
        t = "Json"
    else:
        t = "unknown"
    return f"{t}[]" if is_array else t


columns: dict[str, list[tuple[str, str, bool, bool]]] = defaultdict(list)
for table, column, data_type, nullable, has_default in query(
    """
    select c.table_name, c.column_name,
      case when c.data_type = 'USER-DEFINED' then c.udt_name
           when c.data_type = 'ARRAY' then substr(c.udt_name, 2) || '[]'
           else c.data_type end,
      c.is_nullable = 'YES',
      c.column_default is not null or c.is_identity = 'YES'
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and t.table_type = 'BASE TABLE'
    order by c.table_name, c.column_name
    """
):
    columns[table].append((column, data_type, nullable == "t", has_default == "t"))

relationships: dict[str, list[tuple[str, str, str, str, bool]]] = defaultdict(list)
for table, fk_name, cols, ref_table, ref_cols, one_to_one in query(
    """
    select cl.relname, con.conname,
      (select string_agg(a.attname, ',' order by k.ord)
         from unnest(con.conkey) with ordinality k(attnum, ord)
         join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum),
      ref.relname,
      (select string_agg(a.attname, ',' order by k.ord)
         from unnest(con.confkey) with ordinality k(attnum, ord)
         join pg_attribute a on a.attrelid = con.confrelid and a.attnum = k.attnum),
      exists (
        select 1 from pg_constraint u
        where u.conrelid = con.conrelid and u.contype in ('p', 'u') and u.conkey = con.conkey
      )
    from pg_constraint con
    join pg_class cl on cl.oid = con.conrelid
    join pg_namespace n on n.oid = cl.relnamespace
    join pg_class ref on ref.oid = con.confrelid
    join pg_namespace rn on rn.oid = ref.relnamespace
    where con.contype = 'f' and n.nspname = 'public' and rn.nspname = 'public'
    order by cl.relname, con.conname
    """
):
    relationships[table].append((fk_name, cols, ref_table, ref_cols, one_to_one == "t"))

functions = query(
    """
    select p.proname,
      coalesce(pg_get_function_arguments(p.oid), ''),
      pg_get_function_result(p.oid),
      p.proretset
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and pg_get_function_result(p.oid) <> 'trigger'
    order by p.proname
    """
)


def parse_args(args: str) -> list[tuple[str, str, bool]]:
    result = []
    if not args:
        return result
    for part in args.split(", "):
        has_default = " DEFAULT " in part
        part = part.split(" DEFAULT ")[0]
        name, _, pg_type = part.partition(" ")
        result.append((name, pg_type, has_default))
    return result


def returns_ts(result: str) -> str:
    if result == "void":
        return "undefined"
    if result.startswith("TABLE("):
        inner = result[len("TABLE("):-1]
        fields = []
        for part in inner.split(", "):
            name, _, pg_type = part.partition(" ")
            fields.append(f"{name}: {ts_type(pg_type)}")
        return "{ " + "; ".join(fields) + " }[]"
    if result.startswith("SETOF "):
        return ts_type(result[len("SETOF "):]) + "[]"
    return ts_type(result)


out: list[str] = []
w = out.append
w("// Wygenerowane przez scripts/db/gen-types.py – NIE edytuj ręcznie.")
w("// Docelowo: supabase gen types typescript --local > lib/types/database.ts")
w("")
w("export type Json =")
w("  | string")
w("  | number")
w("  | boolean")
w("  | null")
w("  | { [key: string]: Json | undefined }")
w("  | Json[];")
w("")
w("export type Database = {")
w("  public: {")
w("    Tables: {")
for table in sorted(columns):
    cols = columns[table]
    w(f"      {table}: {{")
    w("        Row: {")
    for name, dt, nullable, _ in cols:
        w(f"          {name}: {ts_type(dt)}{' | null' if nullable else ''};")
    w("        };")
    w("        Insert: {")
    for name, dt, nullable, has_default in cols:
        opt = "?" if (nullable or has_default) else ""
        w(f"          {name}{opt}: {ts_type(dt)}{' | null' if nullable else ''};")
    w("        };")
    w("        Update: {")
    for name, dt, nullable, _ in cols:
        w(f"          {name}?: {ts_type(dt)}{' | null' if nullable else ''};")
    w("        };")
    rels = relationships.get(table, [])
    if not rels:
        w("        Relationships: [];")
        w("      };")
        continue
    w("        Relationships: [")
    for fk_name, fk_cols, ref_table, ref_cols, one_to_one in rels:
        cols_ts = ", ".join(f'"{c}"' for c in fk_cols.split(","))
        ref_ts = ", ".join(f'"{c}"' for c in ref_cols.split(","))
        w("          {")
        w(f'            foreignKeyName: "{fk_name}";')
        w(f"            columns: [{cols_ts}];")
        w(f"            isOneToOne: {'true' if one_to_one else 'false'};")
        w(f'            referencedRelation: "{ref_table}";')
        w(f"            referencedColumns: [{ref_ts}];")
        w("          },")
    w("        ];")
    w("      };")
w("    };")
w("    Views: {")
w("      [_ in never]: never;")
w("    };")
w("    Functions: {")
for name, args, result, _retset in functions:
    parsed = parse_args(args)
    w(f"      {name}: {{")
    if parsed:
        w("        Args: {")
        for arg_name, pg_type, has_default in parsed:
            w(f"          {arg_name}{'?' if has_default else ''}: {ts_type(pg_type)};")
        w("        };")
    else:
        w("        Args: never;")
    w(f"        Returns: {returns_ts(result)};")
    w("      };")
w("    };")
w("    Enums: {")
for name in sorted(enums):
    values = " | ".join(f'"{v}"' for v in enums[name])
    w(f"      {name}: {values};")
w("    };")
w("    CompositeTypes: {")
w("      [_ in never]: never;")
w("    };")
w("  };")
w("};")
w("")
w('type PublicSchema = Database["public"];')
w("")
w('export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"];')
w('export type TablesInsert<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Insert"];')
w('export type TablesUpdate<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Update"];')
w('export type Enums<T extends keyof PublicSchema["Enums"]> = PublicSchema["Enums"][T];')
w("")
w("export const Constants = {")
w("  public: {")
w("    Enums: {")
for name in sorted(enums):
    values = ", ".join(f'"{v}"' for v in enums[name])
    w(f"      {name}: [{values}],")
w("    },")
w("  },")
w("} as const;")

sys.stdout.write("\n".join(out) + "\n")
