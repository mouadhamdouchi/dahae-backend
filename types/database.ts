export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      academic_terms: {
        Row: {
          created_at: string
          ends_on: string
          id: string
          school_year: string
          semester: "s1" | "s2"
          starts_on: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          ends_on: string
          id?: string
          school_year: string
          semester: "s1" | "s2"
          starts_on: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          ends_on?: string
          id?: string
          school_year?: string
          semester?: "s1" | "s2"
          starts_on?: string
          updated_at?: string
        }
        Relationships: []
      }
      access_grant_subjects: {
        Row: {
          grant_id: string
          track_id: string
          track_subject_id: string
        }
        Insert: {
          grant_id: string
          track_id: string
          track_subject_id: string
        }
        Update: {
          grant_id?: string
          track_id?: string
          track_subject_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "access_grant_subjects_grant_id_fkey"
            columns: ["grant_id"]
            isOneToOne: false
            referencedRelation: "access_grants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "access_grant_subjects_same_track_as_grant"
            columns: ["grant_id", "track_id"]
            isOneToOne: false
            referencedRelation: "access_grants"
            referencedColumns: ["id", "track_id"]
          },
          {
            foreignKeyName: "access_grant_subjects_subject_in_track"
            columns: ["track_subject_id", "track_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id", "track_id"]
          },
          {
            foreignKeyName: "access_grant_subjects_track_subject_id_fkey"
            columns: ["track_subject_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      access_grants: {
        Row: {
          created_at: string
          ends_at: string
          granted_at: string
          granted_by: string
          id: string
          note: string | null
          pack_id: string | null
          revoke_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          starts_at: string
          term_id: string
          track_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          ends_at: string
          granted_at?: string
          granted_by: string
          id?: string
          note?: string | null
          pack_id?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          starts_at?: string
          term_id: string
          track_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          ends_at?: string
          granted_at?: string
          granted_by?: string
          id?: string
          note?: string | null
          pack_id?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          starts_at?: string
          term_id?: string
          track_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "access_grants_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "access_grants_pack_id_fkey"
            columns: ["pack_id"]
            isOneToOne: false
            referencedRelation: "packs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "access_grants_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "access_grants_term_id_fkey"
            columns: ["term_id"]
            isOneToOne: false
            referencedRelation: "academic_terms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "access_grants_track_id_fkey"
            columns: ["track_id"]
            isOneToOne: false
            referencedRelation: "tracks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "access_grants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_events: {
        Row: {
          action:
            | "accessGranted"
            | "accessExtended"
            | "accessRevoked"
            | "paymentRecorded"
            | "resourceAdded"
            | "sessionMoved"
            | "sessionProposed"
            | "sessionPublished"
            | "sessionRefused"
            | "courseDrafted"
            | "coursePublished"
            | "courseDeleted"
            | "deletionRequested"
            | "deletionApproved"
            | "deletionRefused"
            | "liveStarted"
            | "liveEnded"
            | "recordingSaved"
            | "recordingRenamed"
            | "recordingDeleted"
            | "teacherAppointed"
            | "teacherSubjectsChanged"
            | "teacherRemoved"
          actor_id: string | null
          actor_role: "student" | "teacher" | "super_admin"
          created_at: string
          id: string
          metadata: Json
          subject_label: string
          target_id: string | null
          target_type: string | null
        }
        Insert: {
          action:
            | "accessGranted"
            | "accessExtended"
            | "accessRevoked"
            | "paymentRecorded"
            | "resourceAdded"
            | "sessionMoved"
            | "sessionProposed"
            | "sessionPublished"
            | "sessionRefused"
            | "courseDrafted"
            | "coursePublished"
            | "courseDeleted"
            | "deletionRequested"
            | "deletionApproved"
            | "deletionRefused"
            | "liveStarted"
            | "liveEnded"
            | "recordingSaved"
            | "recordingRenamed"
            | "recordingDeleted"
            | "teacherAppointed"
            | "teacherSubjectsChanged"
            | "teacherRemoved"
          actor_id?: string | null
          actor_role: "student" | "teacher" | "super_admin"
          created_at?: string
          id?: string
          metadata?: Json
          subject_label: string
          target_id?: string | null
          target_type?: string | null
        }
        Update: {
          action?:
            | "accessGranted"
            | "accessExtended"
            | "accessRevoked"
            | "paymentRecorded"
            | "resourceAdded"
            | "sessionMoved"
            | "sessionProposed"
            | "sessionPublished"
            | "sessionRefused"
            | "courseDrafted"
            | "coursePublished"
            | "courseDeleted"
            | "deletionRequested"
            | "deletionApproved"
            | "deletionRefused"
            | "liveStarted"
            | "liveEnded"
            | "recordingSaved"
            | "recordingRenamed"
            | "recordingDeleted"
            | "teacherAppointed"
            | "teacherSubjectsChanged"
            | "teacherRemoved"
          actor_id?: string | null
          actor_role?: "student" | "teacher" | "super_admin"
          created_at?: string
          id?: string
          metadata?: Json
          subject_label?: string
          target_id?: string | null
          target_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      centers: {
        Row: {
          city: string
          created_at: string
          id: string
          is_active: boolean
          name: string
          slug: string
          updated_at: string
        }
        Insert: {
          city: string
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          slug: string
          updated_at?: string
        }
        Update: {
          city?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      deletion_requests: {
        Row: {
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          id: string
          label: string
          lesson_id: string | null
          reason: string
          requested_at: string
          requested_by: string
          status: "pending" | "approved" | "refused"
          track_subject_id: string
        }
        Insert: {
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          id?: string
          label: string
          lesson_id?: string | null
          reason: string
          requested_at?: string
          requested_by: string
          status?: "pending" | "approved" | "refused"
          track_subject_id: string
        }
        Update: {
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          id?: string
          label?: string
          lesson_id?: string | null
          reason?: string
          requested_at?: string
          requested_by?: string
          status?: "pending" | "approved" | "refused"
          track_subject_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "deletion_requests_decided_by_fkey"
            columns: ["decided_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deletion_requests_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deletion_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deletion_requests_track_subject_id_fkey"
            columns: ["track_subject_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      lesson_progress: {
        Row: {
          completed_at: string | null
          created_at: string
          first_opened_at: string
          last_seen_at: string
          lesson_id: string
          percent: number
          updated_at: string
          user_id: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          first_opened_at?: string
          last_seen_at?: string
          lesson_id: string
          percent?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          first_opened_at?: string
          last_seen_at?: string
          lesson_id?: string
          percent?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lesson_progress_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lesson_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      lessons: {
        Row: {
          available_from: string | null
          available_until: string | null
          created_at: string
          created_by: string | null
          id: string
          is_free_preview: boolean
          position: number
          published: boolean
          semester: "s1" | "s2"
          slug: string
          summary_ar: string
          summary_en: string
          summary_fr: string
          title_ar: string
          title_en: string
          title_fr: string
          track_subject_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          available_from?: string | null
          available_until?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_free_preview?: boolean
          position: number
          published?: boolean
          semester: "s1" | "s2"
          slug: string
          summary_ar: string
          summary_en: string
          summary_fr: string
          title_ar: string
          title_en: string
          title_fr: string
          track_subject_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          available_from?: string | null
          available_until?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_free_preview?: boolean
          position?: number
          published?: boolean
          semester?: "s1" | "s2"
          slug?: string
          summary_ar?: string
          summary_en?: string
          summary_fr?: string
          title_ar?: string
          title_en?: string
          title_fr?: string
          track_subject_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lessons_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_track_subject_id_fkey"
            columns: ["track_subject_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      live_sessions: {
        Row: {
          closed_at: string | null
          created_at: string
          id: string
          opened_at: string
          opened_by: string
          semester: "s1" | "s2"
          session_id: string
          stream_id: string
          term_id: string
          track_subject_id: string
          updated_at: string
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          id?: string
          opened_at?: string
          opened_by: string
          semester: "s1" | "s2"
          session_id: string
          stream_id: string
          term_id: string
          track_subject_id: string
          updated_at?: string
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          id?: string
          opened_at?: string
          opened_by?: string
          semester?: "s1" | "s2"
          session_id?: string
          stream_id?: string
          term_id?: string
          track_subject_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "live_sessions_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "live_sessions_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "live_sessions_stream_id_fkey"
            columns: ["stream_id"]
            isOneToOne: true
            referencedRelation: "streams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "live_sessions_term_id_fkey"
            columns: ["term_id"]
            isOneToOne: false
            referencedRelation: "academic_terms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "live_sessions_track_subject_id_fkey"
            columns: ["track_subject_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      packs: {
        Row: {
          billing: string
          created_at: string
          currency: string
          id: string
          is_demo_price: boolean
          position: number
          price_minor: number
          published: boolean
          slug: string
          subject_count: number
          updated_at: string
        }
        Insert: {
          billing?: string
          created_at?: string
          currency?: string
          id?: string
          is_demo_price?: boolean
          position: number
          price_minor: number
          published?: boolean
          slug: string
          subject_count: number
          updated_at?: string
        }
        Update: {
          billing?: string
          created_at?: string
          currency?: string
          id?: string
          is_demo_price?: boolean
          position?: number
          price_minor?: number
          published?: boolean
          slug?: string
          subject_count?: number
          updated_at?: string
        }
        Relationships: []
      }
      payments: {
        Row: {
          amount_minor: number
          cancel_reason: string | null
          cancelled_at: string | null
          created_at: string
          currency: string
          grant_id: string
          id: string
          method: "cash" | "transfer"
          paid_at: string
          recorded_at: string
          recorded_by: string
          status: string
          updated_at: string
        }
        Insert: {
          amount_minor: number
          cancel_reason?: string | null
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          grant_id: string
          id?: string
          method: "cash" | "transfer"
          paid_at?: string
          recorded_at?: string
          recorded_by: string
          status?: string
          updated_at?: string
        }
        Update: {
          amount_minor?: number
          cancel_reason?: string | null
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          grant_id?: string
          id?: string
          method?: "cash" | "transfer"
          paid_at?: string
          recorded_at?: string
          recorded_by?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_grant_id_fkey"
            columns: ["grant_id"]
            isOneToOne: true
            referencedRelation: "access_grants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          date_of_birth: string | null
          declared_track_id: string | null
          email: string
          first_name: string | null
          full_name: string
          guardian_consent_at: string | null
          guardian_consent_recorded_by: string | null
          guardian_full_name: string | null
          guardian_phone: string | null
          guardian_relationship: string | null
          id: string
          last_name: string | null
          locale: string
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          date_of_birth?: string | null
          declared_track_id?: string | null
          email: string
          first_name?: string | null
          full_name: string
          guardian_consent_at?: string | null
          guardian_consent_recorded_by?: string | null
          guardian_full_name?: string | null
          guardian_phone?: string | null
          guardian_relationship?: string | null
          id: string
          last_name?: string | null
          locale?: string
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          date_of_birth?: string | null
          declared_track_id?: string | null
          email?: string
          first_name?: string | null
          full_name?: string
          guardian_consent_at?: string | null
          guardian_consent_recorded_by?: string | null
          guardian_full_name?: string | null
          guardian_phone?: string | null
          guardian_relationship?: string | null
          id?: string
          last_name?: string | null
          locale?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_declared_track_fkey"
            columns: ["declared_track_id"]
            isOneToOne: false
            referencedRelation: "tracks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profiles_guardian_consent_recorded_by_fkey"
            columns: ["guardian_consent_recorded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      recordings: {
        Row: {
          created_at: string
          ended_at: string
          id: string
          live_id: string | null
          semester: "s1" | "s2"
          session_id: string | null
          started_at: string
          stream_id: string
          title: string | null
          track_subject_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          ended_at: string
          id?: string
          live_id?: string | null
          semester: "s1" | "s2"
          session_id?: string | null
          started_at: string
          stream_id: string
          title?: string | null
          track_subject_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          ended_at?: string
          id?: string
          live_id?: string | null
          semester?: "s1" | "s2"
          session_id?: string | null
          started_at?: string
          stream_id?: string
          title?: string | null
          track_subject_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recordings_live_id_fkey"
            columns: ["live_id"]
            isOneToOne: true
            referencedRelation: "live_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recordings_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recordings_stream_id_fkey"
            columns: ["stream_id"]
            isOneToOne: false
            referencedRelation: "streams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recordings_track_subject_id_fkey"
            columns: ["track_subject_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recordings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      resource_media: {
        Row: {
          created_at: string
          provider: string | null
          provider_public_id: string | null
          resource_id: string
          storage_bucket: string | null
          storage_key: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          provider?: string | null
          provider_public_id?: string | null
          resource_id: string
          storage_bucket?: string | null
          storage_key?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          provider?: string | null
          provider_public_id?: string | null
          resource_id?: string
          storage_bucket?: string | null
          storage_key?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "resource_media_resource_id_fkey"
            columns: ["resource_id"]
            isOneToOne: true
            referencedRelation: "resources"
            referencedColumns: ["id"]
          },
        ]
      }
      resources: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          kind: "pdf" | "video" | "serie" | "correction"
          label_ar: string | null
          label_en: string | null
          label_fr: string | null
          lesson_id: string
          mime_type: string | null
          position: number
          size_bytes: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          kind: "pdf" | "video" | "serie" | "correction"
          label_ar?: string | null
          label_en?: string | null
          label_fr?: string | null
          lesson_id: string
          mime_type?: string | null
          position: number
          size_bytes?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          kind?: "pdf" | "video" | "serie" | "correction"
          label_ar?: string | null
          label_en?: string | null
          label_fr?: string | null
          lesson_id?: string
          mime_type?: string | null
          position?: number
          size_bytes?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "resources_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "resources_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "resources_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      sessions: {
        Row: {
          center_id: string | null
          created_at: string
          end_time: string
          id: string
          modality: "hybrid" | "in_person" | "online"
          proposed_at: string
          proposed_by: string
          published: boolean
          published_at: string | null
          published_by: string | null
          slot: unknown
          start_time: string
          teacher_id: string | null
          track_id: string
          track_subject_id: string
          updated_at: string
          weekday: number
        }
        Insert: {
          center_id?: string | null
          created_at?: string
          end_time: string
          id?: string
          modality?: "hybrid" | "in_person" | "online"
          proposed_at?: string
          proposed_by: string
          published?: boolean
          published_at?: string | null
          published_by?: string | null
          slot?: unknown
          start_time: string
          teacher_id?: string | null
          track_id: string
          track_subject_id: string
          updated_at?: string
          weekday: number
        }
        Update: {
          center_id?: string | null
          created_at?: string
          end_time?: string
          id?: string
          modality?: "hybrid" | "in_person" | "online"
          proposed_at?: string
          proposed_by?: string
          published?: boolean
          published_at?: string | null
          published_by?: string | null
          slot?: unknown
          start_time?: string
          teacher_id?: string | null
          track_id?: string
          track_subject_id?: string
          updated_at?: string
          weekday?: number
        }
        Relationships: [
          {
            foreignKeyName: "sessions_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sessions_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sessions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sessions_subject_in_track"
            columns: ["track_subject_id", "track_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id", "track_id"]
          },
          {
            foreignKeyName: "sessions_teacher_id_fkey"
            columns: ["teacher_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sessions_track_subject_id_fkey"
            columns: ["track_subject_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      settings: {
        Row: {
          completion_threshold: number
          created_at: string
          email: string
          id: boolean
          location: string
          updated_at: string
          updated_by: string | null
          whatsapp_number: string
        }
        Insert: {
          completion_threshold?: number
          created_at?: string
          email: string
          id?: boolean
          location: string
          updated_at?: string
          updated_by?: string | null
          whatsapp_number: string
        }
        Update: {
          completion_threshold?: number
          created_at?: string
          email?: string
          id?: boolean
          location?: string
          updated_at?: string
          updated_by?: string | null
          whatsapp_number?: string
        }
        Relationships: [
          {
            foreignKeyName: "settings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      streams: {
        Row: {
          closed_at: string | null
          created_at: string
          id: string
          ingest_url: string | null
          opened_at: string
          opened_by: string | null
          playback_url: string | null
          provider: string
          provider_stream_id: string | null
          public_id: string
          stream_key: string | null
          updated_at: string
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          id?: string
          ingest_url?: string | null
          opened_at?: string
          opened_by?: string | null
          playback_url?: string | null
          provider: string
          provider_stream_id?: string | null
          public_id: string
          stream_key?: string | null
          updated_at?: string
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          id?: string
          ingest_url?: string | null
          opened_at?: string
          opened_by?: string | null
          playback_url?: string | null
          provider?: string
          provider_stream_id?: string | null
          public_id?: string
          stream_key?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "streams_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      subjects: {
        Row: {
          created_at: string
          id: string
          position: number
          slug: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          position: number
          slug: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          position?: number
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      teacher_subjects: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          id: string
          track_subject_id: string
          user_id: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          id?: string
          track_subject_id: string
          user_id: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          id?: string
          track_subject_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "teacher_subjects_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teacher_subjects_track_subject_id_fkey"
            columns: ["track_subject_id"]
            isOneToOne: false
            referencedRelation: "track_subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teacher_subjects_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      track_subjects: {
        Row: {
          created_at: string
          description_ar: string | null
          description_en: string | null
          description_fr: string | null
          id: string
          modality: "hybrid" | "in_person" | "online"
          published: boolean
          subject_id: string
          track_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description_ar?: string | null
          description_en?: string | null
          description_fr?: string | null
          id?: string
          modality?: "hybrid" | "in_person" | "online"
          published?: boolean
          subject_id: string
          track_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description_ar?: string | null
          description_en?: string | null
          description_fr?: string | null
          id?: string
          modality?: "hybrid" | "in_person" | "online"
          published?: boolean
          subject_id?: string
          track_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "track_subjects_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "track_subjects_track_id_fkey"
            columns: ["track_id"]
            isOneToOne: false
            referencedRelation: "tracks"
            referencedColumns: ["id"]
          },
        ]
      }
      tracks: {
        Row: {
          created_at: string
          filiere: "sciences-economiques" | "sgc" | null
          id: string
          level: "1bac" | "2bac"
          position: number
          published: boolean
          slug: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          filiere?: "sciences-economiques" | "sgc" | null
          id?: string
          level: "1bac" | "2bac"
          position: number
          published?: boolean
          slug: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          filiere?: "sciences-economiques" | "sgc" | null
          id?: string
          level?: "1bac" | "2bac"
          position?: number
          published?: boolean
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          center_id: string | null
          granted_at: string
          granted_by: string | null
          id: string
          role: "student" | "teacher" | "super_admin"
          user_id: string
        }
        Insert: {
          center_id?: string | null
          granted_at?: string
          granted_by?: string | null
          id?: string
          role: "student" | "teacher" | "super_admin"
          user_id: string
        }
        Update: {
          center_id?: string | null
          granted_at?: string
          granted_by?: string | null
          id?: string
          role?: "student" | "teacher" | "super_admin"
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_roles_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      lesson_resource_kinds: {
        Row: {
          kind: "pdf" | "video" | "serie" | "correction" | null
          lesson_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "resources_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      close_live: {
        Args: { p_live: string; p_playback_url?: string; p_title?: string }
        Returns: string
      }
      live_ingest: {
        Args: { p_live: string }
        Returns: {
          ingest_url: string
          stream_key: string
        }[]
      }
      live_playback: { Args: { p_live: string }; Returns: string }
      live_stream_ref: {
        Args: { p_live: string }
        Returns: {
          provider_stream_id: string
          public_id: string
        }[]
      }
      open_live: {
        Args: {
          p_ingest_url: string
          p_playback_url: string
          p_provider: string
          p_public_id: string
          p_session: string
          p_stream_key: string
          p_stream_ref?: string
        }
        Returns: string
      }
      record_guardian_consent: { Args: { p_user: string }; Returns: string }
      recording_playback: { Args: { p_recording: string }; Returns: string }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
