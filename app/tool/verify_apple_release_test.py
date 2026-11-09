import copy
from datetime import datetime, timedelta, timezone
import unittest

from verify_apple_release import COMPONENTS, GROUP, TEAM, validate_component


class SignedCapabilitiesTests(unittest.TestCase):
    def fixture(self, bundle_id):
        info = {"CFBundleIdentifier": bundle_id, "CFBundleVersion": "27"}
        signed = {
            "application-identifier": f"{TEAM}.{bundle_id}",
            "com.apple.developer.team-identifier": TEAM,
            "com.apple.security.application-groups": [GROUP],
            "get-task-allow": False,
        }
        profile = {
            "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=1),
            "Entitlements": copy.deepcopy(signed),
        }
        return info, signed, profile

    def test_signed_groups_are_required_in_every_component(self):
        # Reproduces TestFlight 25/26: valid Apple signatures, correct IDs,
        # but no application-groups entitlement after unsigned cloud export.
        for bundle_id in COMPONENTS.values():
            with self.subTest(bundle_id=bundle_id):
                info, signed, profile = self.fixture(bundle_id)
                del signed["com.apple.security.application-groups"]
                with self.assertRaisesRegex(ValueError, "signature is missing App Group"):
                    validate_component(info, signed, profile, "27", True)

    def test_source_group_cannot_replace_profile_permission(self):
        info, signed, profile = self.fixture("kz.dauam")
        del profile["Entitlements"]["com.apple.security.application-groups"]
        with self.assertRaisesRegex(ValueError, "profile is missing App Group"):
            validate_component(info, signed, profile, "27", True)

    def test_valid_current_components(self):
        for bundle_id in COMPONENTS.values():
            validate_component(*self.fixture(bundle_id), "27", True)

    def test_mixed_build_and_debugging_and_expiry_rejected(self):
        for mutation in ["version", "debug", "expired", "development", "wrong-group", "wrong-team"]:
            with self.subTest(mutation=mutation):
                info, signed, profile = self.fixture("kz.dauam")
                if mutation == "version":
                    info["CFBundleVersion"] = "26"
                elif mutation == "debug":
                    signed["get-task-allow"] = True
                elif mutation == "expired":
                    profile["ExpirationDate"] -= timedelta(days=2)
                elif mutation == "development":
                    profile["ProvisionedDevices"] = ["fixture-device"]
                elif mutation == "wrong-group":
                    signed["com.apple.security.application-groups"] = ["group.unrelated"]
                else:
                    signed["com.apple.developer.team-identifier"] = "OTHER"
                with self.assertRaises(ValueError):
                    validate_component(info, signed, profile, "27", True)


if __name__ == "__main__":
    unittest.main()
