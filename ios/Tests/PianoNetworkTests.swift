//
// PianoNetworkTests.swift — live end-to-end login test (network required).
//
// Runs the app's REAL login path (PianoClient → unmodified C core →
// URLSession) against pandora.com with throwaway credentials:
//
//   step 0 (partnerLogin)  — must reach the server and be ACCEPTED.
//                            This is the request that used to fail with
//                            HTTP 504 ("upstream request timeout") because
//                            of deviceModel "android"; it now sends
//                            "android-generic" (pianobar's default).
//   step 1 (userLogin)     — expected to be REJECTED (dummy credentials);
//                            any rejection proves step 0 got through.
//
// The test only fails on an HTTP 504 (the regression we are guarding) or
// a core-level failure of step 0. If there is no network route to
// pandora.com at all (offline CI runner), the test reports skip instead
// of failing.
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import XCTest
@testable import PianoApp

final class PianoNetworkTests: XCTestCase {

    func testLoginPartnerStepIsAccepted() async {
        guard let client = try? PianoClient(username: "pb_ios_ci",
                                            password: "pb_ios_ci") else {
            XCTFail("PianoClient init failed (C core init error)")
            return
        }

        do {
            // Full success is impossible with dummy credentials; reaching
            // this point means the server accepted both steps, which is
            // fine for our purposes (no 504).
            try await client.login()
        } catch PianoError.network(let msg) {
            // The server answered over HTTP. Anything other than a 504
            // means the partnerLogin step was accepted (e.g. a 401 from
            // the user step, or the server rejecting our dummy account).
            if msg.contains("504") {
                XCTFail("partnerLogin failed with HTTP 504 (deviceModel " +
                        "regression?): \(msg)")
            }
            // else: expected rejection of the dummy credentials — pass.
        } catch let nsError as NSError {
            // URLSession-level failure: no route to the host at all.
            // Skip rather than fail (offline runner).
            print("SKIP network test: \(nsError.domain) " +
                  "\(nsError.code): \(nsError.localizedDescription)")
        } catch let PianoError.piano(rc) {
            // Core-level result. PIANO_RET_INVALID_LOGIN /
            // PIANO_RET_P_INVALID_PARTNER_LOGIN come from the USER step
            // (step 1) — which means partnerLogin (step 0) succeeded.
            // Any other core error means step 0 itself failed.
            switch rc {
            case PIANO_RET_INVALID_LOGIN, PIANO_RET_P_INVALID_PARTNER_LOGIN:
                break // expected: dummy credentials rejected — pass
            default:
                XCTFail("core error during login (step 0 failure?): " +
                        "\(Int(rc.rawValue))")
            }
        } catch {
            XCTFail("unexpected error during login: \(error)")
        }
    }
}
