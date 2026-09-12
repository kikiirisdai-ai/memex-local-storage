// Copyright 2024 The Memex team. All rights reserved.
// Aligned with Flutter Compass app: config registers only Repository/Service,
// not ViewModels. ViewModels are created where the screen is built.

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:memex/data/repositories/memex_router.dart';

/// Shared dependency providers for the app.
/// Only register Repository and Service here; do not register ViewModels.
/// ViewModels are created in the place that builds the screen (route builder
/// or parent widget), using context.read<MemexRouter>() etc.
List<SingleChildWidget> get dependencyProviders => [
      Provider<MemexRouter>(
        create: (_) => MemexRouter(),
      ),
    ];
