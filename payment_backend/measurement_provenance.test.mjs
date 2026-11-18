import test from 'node:test';
import assert from 'node:assert/strict';
import {
  validRecommendationProfile, emptyRecommendationProfile, RecommendationProfilesService,
} from './recommendation_profiles.mjs';

const baseTime = 1793500000000;
const reviewProfile = () => ({
  ...emptyRecommendationProfile(),
  measurements: {Bust: 90, Waist: 65, Hips: 95},
  useProportions: true,
  measurementProvenance: {
    fields: Object.fromEntries(['Bust', 'Waist', 'Hips'].map(label => [label, {
      source: label === 'Waist' ? 'camera-corrected' : 'camera-reviewed',
      recordedAt: baseTime + 2000, tapeCheckedAt: baseTime + 1000,
    }])),
    scan: {
      measurements: {Bust: 90, Waist: 70, Hips: 95},
      heightCm: 168, capturedAt: baseTime, methodVersion: 'two-view-ellipse-v1',
    },
  },
});
function fixture() {
  const data = new Map();
  const service = new RecommendationProfilesService({
    store: {atomic: async action => action({
      get: async path => structuredClone(data.get(path)),
      set: (path, row) => data.set(path, structuredClone(row)),
    })},
    access: async () => ({staff: false}), now: () => baseTime + 3000,
  });
  return {data, service};
}

test('review provenance round-trips privately while final values remain in measurements', async () => {
  const {data, service} = fixture();
  const input = {revision: 0, requestId: 'review', profile: reviewProfile()};
  assert(validRecommendationProfile(input.profile));
  const saved = await service.save('owner', input);
  assert.deepEqual(saved.profile, input.profile);
  assert.deepEqual((await service.get('owner')).profile, input.profile);
  assert.equal((await service.get('other')).profile.measurementProvenance, undefined);
  assert.deepEqual(await service.save('owner', input), saved);
  const summary = data.get('bodyTypeSummaries/owner');
  assert.equal(summary.bodyType, null);
  assert.equal('measurementProvenance' in summary, false);
  assert.equal('measurements' in summary, false);
});

test('legacy saves retain evidence only for unchanged values and never inherit obsolete tape checks', async () => {
  const {service} = fixture();
  await service.save('owner', {revision: 0, requestId: 'review', profile: reviewProfile()});
  const oldClient = reviewProfile();
  delete oldClient.measurementProvenance;
  const same = await service.save('owner', {revision: 1, requestId: 'old-preferences', profile: oldClient});
  assert.deepEqual(same.profile.measurementProvenance, reviewProfile().measurementProvenance);
  oldClient.measurements.Waist = 66;
  const changed = await service.save('owner', {revision: 2, requestId: 'old-edit', profile: oldClient});
  assert.equal(changed.profile.measurementProvenance.fields.Waist, undefined);
  assert.ok(changed.profile.measurementProvenance.fields.Bust);
  oldClient.measurements = {};
  oldClient.useProportions = false;
  const cleared = await service.save('owner', {revision: 3, requestId: 'old-clear', profile: oldClient});
  assert.equal(cleared.profile.measurementProvenance, undefined);
});

test('rejects forged fields, invented certainty, incomplete scans and contradictory verification', () => {
  for (const mutate of [
    p => {p.measurementProvenance.owner = 'other';},
    p => {p.measurementProvenance.scan.accuracy = 100;},
    p => {p.measurementProvenance.scan.image = 'private photo';},
    p => {p.measurementProvenance.scan.methodVersion = 'unknown';},
    p => {p.measurementProvenance.scan.heightCm = 0;},
    p => {delete p.measurementProvenance.scan.measurements.Hips;},
    p => {delete p.measurementProvenance.fields.Bust.tapeCheckedAt;},
    p => {p.measurementProvenance.fields.Bust.tapeCheckedAt = baseTime - 1;},
    p => {p.measurementProvenance.fields.Bust.source = 'camera-corrected';},
    p => {p.measurementProvenance.fields.Waist.source = 'camera-reviewed';},
    p => {p.measurementProvenance.fields.Other = p.measurementProvenance.fields.Bust;},
    p => {delete p.measurements.Bust;},
  ]) {
    const profile = reviewProfile();
    mutate(profile);
    assert.equal(validRecommendationProfile(profile), false);
  }
});

test('manual entry records a source without claiming physical verification', () => {
  const profile = {
    ...emptyRecommendationProfile(), measurements: {Bust: 90},
    measurementProvenance: {fields: {Bust: {source: 'user-entered', recordedAt: baseTime}}},
  };
  assert(validRecommendationProfile(profile));
  assert.equal(profile.measurementProvenance.fields.Bust.tapeCheckedAt, undefined);
  assert(validRecommendationProfile(emptyRecommendationProfile()));
});
