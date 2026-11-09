// Re-sign a fresh archive with compatible identity/profiles, preserving App Groups.
// Optional fourth argument: JSON {identity, keychain, distribution, profiles}.
// Distribution profiles must have no device list and cannot allow debugging.
// Never creates profiles/certificates, builds binaries, installs, or uploads.
const fs = require('fs');
const cp = require('child_process');
const crypto = require('crypto');
const path = require('path');
const os = require('os');
const root = process.argv[2];
const version = process.argv[3];
if (!root || !path.isAbsolute(root) || !/^\d+$/.test(version || '')) {
  throw new Error('Pass absolute fresh Runner.app path and expected build number');
}
const profiles = '/Users/Dom/Library/Developer/Xcode/UserData/Provisioning Profiles';
const config = process.argv[4] ? JSON.parse(fs.readFileSync(process.argv[4], 'utf8')) : {};
const identity = config.identity || 'CE62394F6C7CFD4A94FBFFE09B2138888A45E471';
if (!/^[A-F0-9]{40}$/.test(identity) || (config.keychain && !path.isAbsolute(config.keychain))) {
  throw new Error('Invalid signing identity/keychain');
}
const keychainArgs = config.keychain ? ['--keychain', config.keychain] : [];
const profileByBundle = config.profiles || {
  'kz.dauam': 'd11ec946-6683-4a9d-b039-acee00434f29',
  'kz.dauam.JadwalWidgetExtension': '31c9931a-2d11-43c7-a68a-ed5837fbf864',
  'kz.dauam.watchkitapp': '3f08260f-a76b-42cf-82bb-69da4fbe9527',
  'kz.dauam.watchkitapp.DauamWatchWidgets': '200783d2-ca4f-4877-b70e-37960bcc067c',
};
function run(exe, args, options = {}) {
  return cp.execFileSync(exe, args, {encoding: 'utf8', ...options});
}
function decode(xml) {
  const normalized = xml.replace(/<date>([\s\S]*?)<\/date>/g, '<string>$1</string>')
    .replace(/<data>([\s\S]*?)<\/data>/g, (_, d) => '<string>'+d.replace(/\s/g, '')+'</string>');
  return JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', '-'], {input: normalized}));
}
const bundles = [], binaries = [];
function collect(directory) {
  for (const item of fs.readdirSync(directory, {withFileTypes: true})) {
    const entry = path.join(directory, item.name);
    if (item.isDirectory()) {
      collect(entry);
      if (/\.(app|appex)$/.test(item.name)) bundles.push(entry);
      else if (item.name.endsWith('.framework')) binaries.push(entry);
    } else if (item.isFile() && item.name.endsWith('.dylib')) binaries.push(entry);
  }
}
collect(root);
bundles.push(root);
if (bundles.length !== 4) throw new Error('Expected exactly four app/extension bundles');
// Validate every profile/bundle before changing any signature.
const checked = bundles.map(bundle => {
  const info = decode(run('plutil', ['-convert', 'xml1', '-o', '-', path.join(bundle, 'Info.plist')]));
  const uuid = profileByBundle[info.CFBundleIdentifier];
  if (!uuid || info.CFBundleVersion !== version) throw new Error('Unexpected bundle/version');
  const profilePath = path.join(profiles, uuid + '.mobileprovision');
  const xml = run('security', ['cms', '-D', '-i', profilePath]);
  const p = decode(xml);
  const certs = p.DeveloperCertificates.map(c => crypto.createHash('sha1').update(Buffer.from(c, 'base64')).digest('hex').toUpperCase());
  const application = 'ZV5872VU8H.' + info.CFBundleIdentifier;
  if (!certs.includes(identity) || Date.parse(p.ExpirationDate) < Date.now()
      || (config.distribution
        ? (p.ProvisionedDevices || p.ProvisionsAllDevices || p.Entitlements['get-task-allow'])
        : !p.ProvisionedDevices?.includes('00008150-0008453A01D2401C'))
      || p.Entitlements['com.apple.developer.team-identifier'] !== 'ZV5872VU8H'
      || p.Entitlements['application-identifier'] !== application
      || !p.Entitlements['com.apple.security.application-groups'].includes('group.kz.dauam.shared')) {
    throw new Error('Profile does not authorize the local build/App Group');
  }
  return {bundle, info, profilePath, xml, application};
});
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'dauam-sign-archive-'));
try {
  for (const binary of binaries) {
    run('codesign', ['--force', '--sign', identity, ...keychainArgs, '--timestamp=none', binary]);
  }
  for (const {bundle, info, profilePath, xml, application} of checked) {
    const entitlements = path.join(scratch, info.CFBundleIdentifier + '.xcent');
    run('plutil', ['-extract', 'Entitlements', 'xml1', '-o', entitlements, '-'], {input: xml});
    run('/usr/libexec/PlistBuddy', ['-c', 'Set :keychain-access-groups:0 ' + application, entitlements]);
    fs.copyFileSync(profilePath, path.join(bundle, 'embedded.mobileprovision'));
    run('codesign', ['--force', '--sign', identity, ...keychainArgs, '--entitlements', entitlements,
      '--generate-entitlement-der', '--timestamp=none', bundle]);
    console.log('Signed current bundle:', info.CFBundleIdentifier, version);
  }
  run('codesign', ['--verify', '--deep', '--strict', '--verbose=2', root]);
  console.log('Verified complete current build; frameworks:', binaries.length, 'bundles:', bundles.length);
} finally {
  fs.rmSync(scratch, {recursive: true});
}
