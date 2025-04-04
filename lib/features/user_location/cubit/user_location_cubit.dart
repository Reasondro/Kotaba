import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'user_location_state.dart';

class UserLocationCubit extends Cubit<UserLocationState> {
  StreamSubscription<Position>? _positionStreamSubscription;
  final LocationSettings _locationSettings;
  final Duration _debounceDuration;

  // ?Keep track if permission was requested during the current 'startTracking' call
  // ?to avoid asking multiple times if already denied in the same flow.
  bool _permissionRequested = false;

  UserLocationCubit({
    LocationAccuracy accuracy =
        LocationAccuracy.bestForNavigation, //? default for tracking
    int distanceFilter = 2, //? update only after x meters change
    Duration debounceDuration = const Duration(
      milliseconds: 500,
      // milliseconds: 10000, //? fuck around and find out
    ), // Optional debouncing
  }) : _locationSettings = LocationSettings(
         accuracy: accuracy,
         distanceFilter: distanceFilter,
         // TODO  adding timeLimit for Android foreground service if needed later
       ),
       _debounceDuration = debounceDuration,
       //  debounceDuration ??
       //  const Duration(milliseconds: 500), // Default 500ms debounce
       super(UserLocationInitial());

  Future<void> startTracking() async {
    // Prevent starting if already tracking or loading
    if (state is UserLocationTracking || state is UserLocationLoading) return;

    emit(UserLocationLoading());
    _permissionRequested = false; // Reset permission request flag

    try {
      //! 1. Check Location Service Enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        emit(UserLocationServiceDisabled());
        return;
      }

      //! 2. Check and Request Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        _permissionRequested = true;
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          emit(UserLocationPermissionDenied());
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        emit(UserLocationPermissionDeniedForever());
        return;
      }

      //! 3. Permission Granted - Start Listening
      await _positionStreamSubscription?.cancel(); // Cancel any previous stream

      //? Get last known position first for faster initial feedback (optional)
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && !isClosed) {
        emit(UserLocationTracking(position: lastKnown));
      }

      final Stream<Position> positionStream = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      );

      //? Apply debounce if duration is greater than zero
      final Stream<Position> streamToListen =
          (_debounceDuration > Duration.zero)
              ? positionStream.debounceTime(_debounceDuration)
              : positionStream;

      _positionStreamSubscription = streamToListen.listen(
        (Position pos) {
          if (!isClosed) {
            //? Check if cubit is still active
            print("Location Emitted: ${pos.latitude}, ${pos.longitude}");
            emit(UserLocationTracking(position: pos));
          }
        },
        onError: (error) {
          //? Handle potential errors from the stream (e.g., GPS signal loss)
          print("Location Stream Error: $error");
          if (!isClosed) {
            emit(UserLocationError(message: "Error getting location: $error"));
            // Optionally try restarting tracking after an error? Depends on desired behavior.
            // stopTracking();
          }
        },
        onDone: () {
          //? Stream closed unexpectedly?
          if (!isClosed && state is UserLocationTracking) {
            // If we were tracking and the stream just stops, maybe emit initial?
            print("Location stream done.");
            emit(UserLocationInitial()); // Or another appropriate state
          }
        },
        cancelOnError: false, //? Keep listening even after an error if desired
      );

      print("User location tracking started.");
    } catch (e) {
      print("Error starting location tracking: $e");
      if (!isClosed) {
        // Handle errors during setup (e.g., platform exceptions)
        if (e is PermissionRequestInProgressException) {
          emit(
            UserLocationError(
              message: "Permission request already in progress.",
            ),
          );
        } else if (e is LocationServiceDisabledException) {
          emit(UserLocationServiceDisabled());
        } else {
          emit(
            UserLocationError(
              message: "Failed to start tracking: ${e.toString()}",
            ),
          );
        }
      }
    }
  }

  // You might want a method to check permission without starting tracking
  Future<LocationPermission> checkPermissionStatus() async {
    return await Geolocator.checkPermission();
  }

  Future<bool> isServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    if (state is! UserLocationInitial) {
      // Avoid emitting initial if already initial
      emit(UserLocationInitial());
    }
    print("User location tracking stopped.");
  }

  @override
  Future<void> close() {
    stopTracking(); // Ensure stream is cancelled when Cubit is closed
    return super.close();
  }
}
