//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:lumen/api/date_serializer.dart';
import 'package:lumen/api/model/date.dart';

import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
import 'package:lumen/api/model/create_symptoms_response.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/cycle_day_response.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/goal_selection.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/api/model/hormone_prefs_response.dart';
import 'package:lumen/api/model/hormone_selection.dart';
import 'package:lumen/api/model/http_validation_problem_details.dart';
import 'package:lumen/api/model/log_cycle_day_request.dart';
import 'package:lumen/api/model/log_cycle_event_request.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/notification_category_selection.dart';
import 'package:lumen/api/model/notification_prefs_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_start_request.dart';
import 'package:lumen/api/model/onboarding_start_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/api/model/phase_override_boundary.dart';
import 'package:lumen/api/model/phase_override_input.dart';
import 'package:lumen/api/model/phase_overrides_response.dart';
import 'package:lumen/api/model/problem_details.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
import 'package:lumen/api/model/register_device_request.dart';
import 'package:lumen/api/model/register_device_response.dart';
import 'package:lumen/api/model/replace_symptom_request.dart';
import 'package:lumen/api/model/save_baseline_request.dart';
import 'package:lumen/api/model/save_goals_request.dart';
import 'package:lumen/api/model/save_hormone_prefs_request.dart';
import 'package:lumen/api/model/save_notification_prefs_request.dart';
import 'package:lumen/api/model/save_onboarding_cycle_request.dart';
import 'package:lumen/api/model/save_phase_overrides_request.dart';
import 'package:lumen/api/model/symptom_entry_input.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/api/model/update_cycle_settings_request.dart';
import 'package:lumen/api/model/update_me_request.dart';

part 'serializers.g.dart';

@SerializersFor([
  BaselineResponse,
  CreateSymptomsRequest,
  CreateSymptomsResponse,
  CycleCalendarDay,
  CycleCalendarResponse,
  CycleDayLogResponse,
  CycleDayResponse,
  CycleEventResponse,
  CyclePhaseAvailabilityResponse,
  CycleSettingsResponse,
  GoalSelection,
  GoalsResponse,
  HormonePrefsResponse,
  HormoneSelection,
  HttpValidationProblemDetails,
  LogCycleDayRequest,
  LogCycleEventRequest,
  MeResponse,
  NotificationCategorySelection,
  NotificationPrefsResponse,
  OnboardingCompleteResponse,
  OnboardingCycleResponse,
  OnboardingStartRequest,
  OnboardingStartResponse,
  OnboardingStateResponse,
  PhaseOverrideBoundary,
  PhaseOverrideInput,
  PhaseOverridesResponse,
  ProblemDetails,
  QuickCheckinRequest,
  QuickCheckinResponse,
  RegisterDeviceRequest,
  RegisterDeviceResponse,
  ReplaceSymptomRequest,
  SaveBaselineRequest,
  SaveGoalsRequest,
  SaveHormonePrefsRequest,
  SaveNotificationPrefsRequest,
  SaveOnboardingCycleRequest,
  SavePhaseOverridesRequest,
  SymptomEntryInput,
  SymptomListResponse,
  SymptomResponse,
  UpdateCycleSettingsRequest,
  UpdateMeRequest,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer()))
    .build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
