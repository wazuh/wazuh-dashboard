/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */

import { IRouter } from 'opensearch-dashboards/server';
import { ABOUT_API_ROUTE } from '../../common/constants';

export function defineRoutes(router: IRouter) {
  router.get(
    {
      path: ABOUT_API_ROUTE,
      validate: false,
    },
    async (context, _request, response) => {
      try {
        const osResp = await context.core.opensearch.client.asInternalUser.transport.request({
          method: 'GET',
          path: '/',
        });
        const clusterUuid = osResp?.body?.cluster_uuid ?? null;

        return response.ok({
          body: { clusterUuid },
        });
      } catch (error) {
        return response.customError({
          statusCode: error?.statusCode || 500,
          body: { message: error?.message || 'Unable to retrieve the cluster UUID.' },
        });
      }
    }
  );
}
