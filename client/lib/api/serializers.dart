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

import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/onboarding_start_request.dart';
import 'package:lumen/api/model/problem_details.dart';
import 'package:lumen/api/model/update_me_request.dart';

part 'serializers.g.dart';

@SerializersFor([
  MeResponse,
  OnboardingStartRequest,
  ProblemDetails,
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
