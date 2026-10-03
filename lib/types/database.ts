// Wygenerowane przez scripts/db/gen-types.py – NIE edytuj ręcznie.
// Docelowo: supabase gen types typescript --local > lib/types/database.ts

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string;
          actor_id: string | null;
          created_at: string;
          id: number;
          payload: Json;
        };
        Insert: {
          action: string;
          actor_id?: string | null;
          created_at?: string;
          id?: number;
          payload?: Json;
        };
        Update: {
          action?: string;
          actor_id?: string | null;
          created_at?: string;
          id?: number;
          payload?: Json;
        };
        Relationships: [];
      };
      availability: {
        Row: {
          date: string;
          employee_id: string;
          end_time: string | null;
          kind: Database["public"]["Enums"]["availability_kind"];
          start_time: string | null;
          updated_at: string;
        };
        Insert: {
          date: string;
          employee_id: string;
          end_time?: string | null;
          kind: Database["public"]["Enums"]["availability_kind"];
          start_time?: string | null;
          updated_at?: string;
        };
        Update: {
          date?: string;
          employee_id?: string;
          end_time?: string | null;
          kind?: Database["public"]["Enums"]["availability_kind"];
          start_time?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "availability_employee_id_fkey";
            columns: ["employee_id"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
        ];
      };
      employees: {
        Row: {
          active: boolean;
          created_at: string;
          department: Database["public"]["Enums"]["department"];
          full_name: string;
          id: string;
          role: Database["public"]["Enums"]["app_role"];
          swaps_require_approval: boolean;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          department: Database["public"]["Enums"]["department"];
          full_name: string;
          id: string;
          role?: Database["public"]["Enums"]["app_role"];
          swaps_require_approval?: boolean;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          department?: Database["public"]["Enums"]["department"];
          full_name?: string;
          id?: string;
          role?: Database["public"]["Enums"]["app_role"];
          swaps_require_approval?: boolean;
        };
        Relationships: [];
      };
      notifications: {
        Row: {
          created_at: string;
          emailed_at: string | null;
          employee_id: string;
          id: string;
          kind: string;
          message: string;
          payload: Json;
          read_at: string | null;
        };
        Insert: {
          created_at?: string;
          emailed_at?: string | null;
          employee_id: string;
          id?: string;
          kind: string;
          message: string;
          payload?: Json;
          read_at?: string | null;
        };
        Update: {
          created_at?: string;
          emailed_at?: string | null;
          employee_id?: string;
          id?: string;
          kind?: string;
          message?: string;
          payload?: Json;
          read_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "notifications_employee_id_fkey";
            columns: ["employee_id"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
        ];
      };
      schedule_months: {
        Row: {
          availability_deadline: string | null;
          created_at: string;
          id: string;
          month: string;
          published_at: string | null;
          reminder_sent_at: string | null;
          status: Database["public"]["Enums"]["month_status"];
        };
        Insert: {
          availability_deadline?: string | null;
          created_at?: string;
          id?: string;
          month: string;
          published_at?: string | null;
          reminder_sent_at?: string | null;
          status?: Database["public"]["Enums"]["month_status"];
        };
        Update: {
          availability_deadline?: string | null;
          created_at?: string;
          id?: string;
          month?: string;
          published_at?: string | null;
          reminder_sent_at?: string | null;
          status?: Database["public"]["Enums"]["month_status"];
        };
        Relationships: [];
      };
      schedules: {
        Row: {
          archived_at: string | null;
          created_at: string;
          id: string;
          name: string;
          type: Database["public"]["Enums"]["department"];
        };
        Insert: {
          archived_at?: string | null;
          created_at?: string;
          id?: string;
          name: string;
          type: Database["public"]["Enums"]["department"];
        };
        Update: {
          archived_at?: string | null;
          created_at?: string;
          id?: string;
          name?: string;
          type?: Database["public"]["Enums"]["department"];
        };
        Relationships: [];
      };
      shift_templates: {
        Row: {
          created_at: string;
          end_time: string;
          id: string;
          name: string;
          schedule_id: string;
          start_time: string;
        };
        Insert: {
          created_at?: string;
          end_time: string;
          id?: string;
          name: string;
          schedule_id: string;
          start_time: string;
        };
        Update: {
          created_at?: string;
          end_time?: string;
          id?: string;
          name?: string;
          schedule_id?: string;
          start_time?: string;
        };
        Relationships: [
          {
            foreignKeyName: "shift_templates_schedule_id_fkey";
            columns: ["schedule_id"];
            isOneToOne: false;
            referencedRelation: "schedules";
            referencedColumns: ["id"];
          },
        ];
      };
      shifts: {
        Row: {
          created_at: string;
          date: string;
          employee_id: string | null;
          end_time: string;
          id: string;
          schedule_id: string;
          start_time: string;
          template_id: string | null;
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          date: string;
          employee_id?: string | null;
          end_time: string;
          id?: string;
          schedule_id: string;
          start_time: string;
          template_id?: string | null;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          date?: string;
          employee_id?: string | null;
          end_time?: string;
          id?: string;
          schedule_id?: string;
          start_time?: string;
          template_id?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "shifts_employee_id_fkey";
            columns: ["employee_id"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "shifts_schedule_id_fkey";
            columns: ["schedule_id"];
            isOneToOne: false;
            referencedRelation: "schedules";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "shifts_template_id_fkey";
            columns: ["template_id"];
            isOneToOne: false;
            referencedRelation: "shift_templates";
            referencedColumns: ["id"];
          },
        ];
      };
      swap_requests: {
        Row: {
          accepted_by: string | null;
          alerted_at: string | null;
          created_at: string;
          decided_by: string | null;
          exchange_shift_id: string | null;
          id: string;
          requester_id: string;
          resolved_at: string | null;
          shift_id: string;
          status: Database["public"]["Enums"]["swap_status"];
          target_id: string | null;
        };
        Insert: {
          accepted_by?: string | null;
          alerted_at?: string | null;
          created_at?: string;
          decided_by?: string | null;
          exchange_shift_id?: string | null;
          id?: string;
          requester_id: string;
          resolved_at?: string | null;
          shift_id: string;
          status?: Database["public"]["Enums"]["swap_status"];
          target_id?: string | null;
        };
        Update: {
          accepted_by?: string | null;
          alerted_at?: string | null;
          created_at?: string;
          decided_by?: string | null;
          exchange_shift_id?: string | null;
          id?: string;
          requester_id?: string;
          resolved_at?: string | null;
          shift_id?: string;
          status?: Database["public"]["Enums"]["swap_status"];
          target_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "swap_requests_accepted_by_fkey";
            columns: ["accepted_by"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "swap_requests_decided_by_fkey";
            columns: ["decided_by"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "swap_requests_exchange_shift_id_fkey";
            columns: ["exchange_shift_id"];
            isOneToOne: false;
            referencedRelation: "shifts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "swap_requests_requester_id_fkey";
            columns: ["requester_id"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "swap_requests_shift_id_fkey";
            columns: ["shift_id"];
            isOneToOne: false;
            referencedRelation: "shifts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "swap_requests_target_id_fkey";
            columns: ["target_id"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      accept_swap_request: {
        Args: {
          p_request_id: string;
          p_exchange_shift_id?: string;
        };
        Returns: Database["public"]["Enums"]["swap_status"];
      };
      archive_schedule: {
        Args: {
          p_schedule_id: string;
        };
        Returns: undefined;
      };
      assign_shift: {
        Args: {
          p_shift_id: string;
          p_employee_id?: string;
        };
        Returns: Json;
      };
      cancel_swap_request: {
        Args: {
          p_request_id: string;
        };
        Returns: undefined;
      };
      create_swap_request: {
        Args: {
          p_shift_id: string;
          p_target_id?: string;
          p_exchange_shift_id?: string;
        };
        Returns: string;
      };
      current_app_role: {
        Args: never;
        Returns: Database["public"]["Enums"]["app_role"];
      };
      current_department: {
        Args: never;
        Returns: Database["public"]["Enums"]["department"];
      };
      decide_swap: {
        Args: {
          p_request_id: string;
          p_approve: boolean;
        };
        Returns: Database["public"]["Enums"]["swap_status"];
      };
      delete_schedule: {
        Args: {
          p_schedule_id: string;
          p_confirm_name: string;
        };
        Returns: undefined;
      };
      eligible_takers: {
        Args: {
          p_shift_id: string;
        };
        Returns: { employee_id: string; full_name: string; declared_available: boolean }[];
      };
      is_manager: {
        Args: never;
        Returns: boolean;
      };
      is_month_collecting: {
        Args: {
          d: string;
        };
        Returns: boolean;
      };
      is_month_published: {
        Args: {
          d: string;
        };
        Returns: boolean;
      };
      is_owner: {
        Args: never;
        Returns: boolean;
      };
      month_start: {
        Args: {
          d: string;
        };
        Returns: string;
      };
      pl_date: {
        Args: {
          d: string;
        };
        Returns: string;
      };
      pl_hours: {
        Args: {
          s: string;
          e: string;
        };
        Returns: string;
      };
      pl_month: {
        Args: {
          d: string;
        };
        Returns: string;
      };
      publish_month: {
        Args: {
          p_month: string;
        };
        Returns: undefined;
      };
      reject_swap_request: {
        Args: {
          p_request_id: string;
        };
        Returns: undefined;
      };
      respond_to_swap_offer: {
        Args: {
          p_request_id: string;
          p_accept: boolean;
        };
        Returns: Database["public"]["Enums"]["swap_status"];
      };
      restore_schedule: {
        Args: {
          p_schedule_id: string;
        };
        Returns: undefined;
      };
      shift_starts_at: {
        Args: {
          d: string;
          t: string;
        };
        Returns: string;
      };
      swap_problem: {
        Args: {
          p_shift_id: string;
          p_taker_id: string;
          p_exchange_shift_id?: string;
        };
        Returns: string;
      };
    };
    Enums: {
      app_role: "owner" | "scheduler" | "employee";
      availability_kind: "all_day" | "hours" | "unavailable";
      department: "sales" | "production";
      month_status: "collecting" | "drafting" | "published";
      swap_status: "open" | "awaiting_requester" | "pending_approval" | "done" | "rejected" | "cancelled" | "expired";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type PublicSchema = Database["public"];

export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"];
export type TablesInsert<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Insert"];
export type TablesUpdate<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Update"];
export type Enums<T extends keyof PublicSchema["Enums"]> = PublicSchema["Enums"][T];

export const Constants = {
  public: {
    Enums: {
      app_role: ["owner", "scheduler", "employee"],
      availability_kind: ["all_day", "hours", "unavailable"],
      department: ["sales", "production"],
      month_status: ["collecting", "drafting", "published"],
      swap_status: ["open", "awaiting_requester", "pending_approval", "done", "rejected", "cancelled", "expired"],
    },
  },
} as const;
