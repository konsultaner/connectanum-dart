import 'package:connectanum_router/src/router/state/procedure.dart';
import 'package:connectanum_router/src/router/state/subscription.dart';
import 'package:test/test.dart';

void main() {
  group('SubscriptionEntry', () {
    test('matches topics using prefix semantics from spec examples', () {
      final entry = SubscriptionEntry(
        id: 1,
        topic: 'com.myapp.topic.emergency',
        matchPolicy: TopicMatchPolicy.prefix,
      );

      expect(entry.matchesTopic('com.myapp.topic.emergency'), isTrue);
      expect(entry.matchesTopic('com.myapp.topic.emergency.11'), isTrue);
      expect(entry.matchesTopic('com.myapp.topic.emergency-low'), isTrue);
      expect(
        entry.matchesTopic('com.myapp.topic.emergency.category.severe'),
        isTrue,
      );
      expect(entry.matchesTopic('com.myapp.topic.emerge'), isFalse);
      expect(entry.matchesTopic('com.myapp.topics.emergency'), isFalse);
    });

    test('matches wildcard topics across single URI components', () {
      final entry = SubscriptionEntry(
        id: 2,
        topic: 'com.myapp..userevent',
        matchPolicy: TopicMatchPolicy.wildcard,
      );

      expect(entry.matchesTopic('com.myapp.foo.userevent'), isTrue);
      expect(entry.matchesTopic('com.myapp.bar.userevent'), isTrue);
      expect(entry.matchesTopic('com.myapp.a12.userevent'), isTrue);
      expect(entry.matchesTopic('com.myapp.foo.userevent.bar'), isFalse);
      expect(entry.matchesTopic('com.myapp.foo.user'), isFalse);
      expect(entry.matchesTopic('com.myapp2.foo.userevent'), isFalse);
    });

    test('accepts prefix patterns that end with a dot', () {
      final entry = SubscriptionEntry(
        id: 3,
        topic: 'status.',
        matchPolicy: TopicMatchPolicy.prefix,
      );

      expect(entry.matchesTopic('status.update'), isTrue);
      expect(entry.matchesTopic('status.'), isTrue);
      expect(entry.matchesTopic('statuschange'), isFalse);
    });
  });

  group('SubscriptionAtlas', () {
    SubscriptionEntry _subscription(
      int id,
      String topic,
      TopicMatchPolicy policy,
    ) => SubscriptionEntry(id: id, topic: topic, matchPolicy: policy);

    test(
      'orders matches exact → prefix specificity → wildcard specificity',
      () {
        final atlas = SubscriptionAtlas();
        atlas.exact['com.advanced.topic'] = _subscription(
          1,
          'com.advanced.topic',
          TopicMatchPolicy.exact,
        );
        atlas.prefixes['com.advanced.'] = _subscription(
          2,
          'com.advanced.',
          TopicMatchPolicy.prefix,
        );
        atlas.prefixes['com.'] = _subscription(
          3,
          'com.',
          TopicMatchPolicy.prefix,
        );
        atlas.wildcards['com.advanced.'] = _subscription(
          4,
          'com.advanced.',
          TopicMatchPolicy.wildcard,
        );
        atlas.wildcards['com..topic'] = _subscription(
          5,
          'com..topic',
          TopicMatchPolicy.wildcard,
        );

        final matches = atlas.match('com.advanced.topic').toList();
        expect(matches.map((entry) => entry.id), equals(<int>[1, 2, 3, 4, 5]));
      },
    );

    test('prefers wildcard with longer literal blocks', () {
      final atlas = SubscriptionAtlas();
      atlas.wildcards['a1.b2..d4.e5'] = _subscription(
        10,
        'a1.b2..d4.e5',
        TopicMatchPolicy.wildcard,
      );
      atlas.wildcards['a1...d4.e5'] = _subscription(
        11,
        'a1...d4.e5',
        TopicMatchPolicy.wildcard,
      );

      final matches = atlas.match('a1.b2.c3.d4.e5').toList();
      expect(matches.map((entry) => entry.id), equals(<int>[10, 11]));
    });

    test('uses id as final tiebreaker when literal stats equal', () {
      final atlas = SubscriptionAtlas();
      atlas.wildcards['a1.b2..d4.e5'] = _subscription(
        30,
        'a1.b2..d4.e5',
        TopicMatchPolicy.wildcard,
      );
      atlas.wildcards['a1.b2.c3..e5'] = _subscription(
        31,
        'a1.b2.c3..e5',
        TopicMatchPolicy.wildcard,
      );

      final matches = atlas.match('a1.b2.c3.d4.e5').toList();
      expect(matches.map((entry) => entry.id), equals(<int>[30, 31]));
    });
  });

  group('ProcedureEntry', () {
    ProcedureEntry _entry(
      String uri, {
      ProcedureMatchPolicy match = ProcedureMatchPolicy.exact,
    }) {
      return ProcedureEntry(
        registrationId: uri.hashCode,
        procedure: uri,
        matchPolicy: match,
      );
    }

    test('prefix matching respects URI component boundaries (spec)', () {
      final prefix = _entry('a1.b2.c3', match: ProcedureMatchPolicy.prefix);

      expect(prefix.matchesProcedure('a1.b2.c3'), isTrue);
      expect(prefix.matchesProcedure('a1.b2.c3.d4'), isTrue);
      expect(prefix.matchesProcedure('a1.b2.c3.d4.e5'), isTrue);
      expect(prefix.matchesProcedure('a1.b2.c33.d4.e5'), isFalse);
      expect(prefix.matchesProcedure('a1.b2.c33'), isFalse);
      expect(prefix.matchesProcedure('a1.b3.c3'), isFalse);
    });

    test('wildcard matching follows advanced profile ordering example', () {
      final wildcardSpecific = _entry(
        'a1.b2..d4.e5',
        match: ProcedureMatchPolicy.wildcard,
      );
      final wildcardGeneric = _entry(
        'a1.b2..d4.e5..g7',
        match: ProcedureMatchPolicy.wildcard,
      );

      expect(wildcardSpecific.matchesProcedure('a1.b2.c55.d4.e5'), isTrue);
      expect(wildcardSpecific.matchesProcedure('a1.b2.c33.d4.e5'), isTrue);
      expect(
        wildcardSpecific.matchesProcedure('a1.b2.c88.d4.e5.f6.g7'),
        isFalse,
      );
      expect(wildcardGeneric.matchesProcedure('a1.b2.c88.d4.e5.f6.g7'), isTrue);
      expect(wildcardGeneric.matchesProcedure('a1.b2.c88.d4.e5'), isFalse);
    });

    test('accepts prefix registrations that end with a dot', () {
      final prefix = _entry('service.', match: ProcedureMatchPolicy.prefix);

      expect(prefix.matchesProcedure('service.health'), isTrue);
      expect(prefix.matchesProcedure('service.'), isTrue);
      expect(prefix.matchesProcedure('servicehealth'), isFalse);
    });
  });

  group('ProcedureAtlas', () {
    ProcedureEntry _register(
      ProcedureAtlas atlas,
      int id,
      String procedure,
      ProcedureMatchPolicy policy,
    ) {
      final entry = atlas.findOrCreate(
        procedure: procedure,
        matchPolicy: policy,
        registrationId: id,
        invocationPolicy: InvocationPolicy.single,
      );
      return entry;
    }

    test('selects best registration following advanced profile spec', () {
      final atlas = ProcedureAtlas();
      _register(atlas, 1, 'a1.b2.c3.d4.e55', ProcedureMatchPolicy.exact);
      _register(atlas, 2, 'a1.b2.c3', ProcedureMatchPolicy.prefix);
      _register(atlas, 3, 'a1.b2.c3.d4', ProcedureMatchPolicy.prefix);
      _register(atlas, 4, 'a1.b2..d4.e5', ProcedureMatchPolicy.wildcard);
      _register(atlas, 5, 'a1.b2.c33..e5', ProcedureMatchPolicy.wildcard);
      _register(atlas, 6, 'a1.b2..d4.e5..g7', ProcedureMatchPolicy.wildcard);
      _register(atlas, 7, 'a1.b2..d4..f6.g7', ProcedureMatchPolicy.wildcard);

      expect(atlas.match('a1.b2.c3.d4.e55')?.registrationId, equals(1));
      expect(atlas.match('a1.b2.c3.d98.e74')?.registrationId, equals(2));
      expect(atlas.match('a1.b2.c3.d4.e325')?.registrationId, equals(3));
      expect(atlas.match('a1.b2.c55.d4.e5')?.registrationId, equals(4));
      expect(atlas.match('a1.b2.c33.d4.e5')?.registrationId, equals(5));
      expect(atlas.match('a1.b2.c88.d4.e5.f6.g7')?.registrationId, equals(6));
      expect(atlas.match('a2.b2.c2.d2.e2'), isNull);
    });

    test('prefers wildcard with longer leading literal blocks', () {
      final atlas = ProcedureAtlas();
      _register(atlas, 40, 'a1.b2..d4.e5', ProcedureMatchPolicy.wildcard);
      _register(atlas, 41, 'a1.b2.c3..e5', ProcedureMatchPolicy.wildcard);

      expect(atlas.match('a1.b2.c3.d4.e5')?.registrationId, equals(41));
      expect(atlas.match('a1.b2.x3.d4.e5')?.registrationId, equals(40));
    });
  });
}
