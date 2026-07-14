


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."catalog" (
    "id" bigint NOT NULL,
    "nhom_san_pham" "text",
    "bo_vat_tu" "text",
    "san_pham" "text",
    "don_gia" numeric,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."catalog" OWNER TO "postgres";


ALTER TABLE "public"."catalog" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."catalog_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."sale_target" (
    "id" bigint NOT NULL,
    "nam_tai_chinh" "text",
    "thang_ke_hoach" "text",
    "mien" "text",
    "ps" "text",
    "khach_hang" "text",
    "ma_khach_hang" "text",
    "nhom_san_pham" "text",
    "san_pham" "text",
    "bo_vat_tu" "text",
    "quota_thau_cu_con_lai" numeric,
    "thang_thau_chinh" "text",
    "thoi_gian_thau_chinh" numeric,
    "quota_thau_chinh" numeric,
    "thang_thau_bo_sung" "text",
    "quota_bo_sung" numeric,
    "sl_ke_hoach_dau_nam" numeric,
    "sl_ke_hoach_update" numeric,
    "don_gia" numeric,
    "doanh_thu_kh_dau_nam" numeric,
    "doanh_thu_kh_update" numeric,
    "chenh_lech_doanh_thu_kh" numeric,
    "giai_trinh" "text",
    "sl_thuc_hien" numeric,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sale_target" OWNER TO "postgres";


ALTER TABLE "public"."sale_target" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."sale_target_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."users" (
    "username" "text" NOT NULL,
    "password_hash" "text" NOT NULL,
    "role" "text" NOT NULL,
    "scope" "text",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."catalog"
    ADD CONSTRAINT "catalog_bo_vat_tu_san_pham_key" UNIQUE ("bo_vat_tu", "san_pham");



ALTER TABLE ONLY "public"."catalog"
    ADD CONSTRAINT "catalog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sale_target"
    ADD CONSTRAINT "sale_target_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("username");



ALTER TABLE "public"."catalog" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sale_target" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";


















GRANT ALL ON TABLE "public"."catalog" TO "anon";
GRANT ALL ON TABLE "public"."catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."catalog" TO "service_role";



GRANT ALL ON SEQUENCE "public"."catalog_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."catalog_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."catalog_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."sale_target" TO "anon";
GRANT ALL ON TABLE "public"."sale_target" TO "authenticated";
GRANT ALL ON TABLE "public"."sale_target" TO "service_role";



GRANT ALL ON SEQUENCE "public"."sale_target_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."sale_target_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."sale_target_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































