/**
 * Accès à l'API Google Play Developer avec le compte de service des fonctions.
 * Ce compte doit être invité dans la Play Console (voir le README de Buteo).
 */

import { androidpublisher, auth } from "@googleapis/androidpublisher";
import { PACKAGE_NAME, PlayApi } from "./purchases";

export function googlePlayApi(): PlayApi {
  const client = androidpublisher({
    version: "v3",
    auth: new auth.GoogleAuth({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] }),
  });
  return {
    async subscription(token) {
      const { data } = await client.purchases.subscriptionsv2.get({ packageName: PACKAGE_NAME, token });
      const item = data.lineItems?.[0];
      return {
        productId: item?.productId ?? "",
        state: data.subscriptionState ?? "",
        expiry: item?.expiryTime ? new Date(item.expiryTime) : null,
        acknowledged: data.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        orderId: item?.latestSuccessfulOrderId ?? undefined,
      };
    },
    async acknowledgeSubscription(productId, token) {
      await client.purchases.subscriptions.acknowledge({
        packageName: PACKAGE_NAME,
        subscriptionId: productId,
        token,
        requestBody: {},
      });
    },
    async product(productId, token) {
      const { data } = await client.purchases.products.get({ packageName: PACKAGE_NAME, productId, token });
      return { purchased: data.purchaseState === 0, orderId: data.orderId ?? undefined };
    },
  };
}
