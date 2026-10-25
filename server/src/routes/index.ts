import { Router } from 'express';
import { authRouter } from './auth.js';
import { friendRequestsRouter } from './friendRequests.js';
import { friendsRouter } from './friends.js';
import { gesturesRouter } from './gestures.js';
import { hangoutsRouter } from './hangouts.js';
import { ingestRouter } from './ingest.js';
import { nudgesRouter } from './nudges.js';
import { privacyRouter } from './privacy.js';
import { settingsRouter } from './settings.js';
import { surprisesRouter } from './surprises.js';
import { twinRouter } from './twin.js';
import { usersRouter } from './users.js';

export const apiRouter = Router();

apiRouter.use(usersRouter);
apiRouter.use(friendsRouter);
apiRouter.use(hangoutsRouter);
apiRouter.use(friendRequestsRouter);
apiRouter.use(authRouter);
apiRouter.use(ingestRouter);
apiRouter.use(twinRouter);
apiRouter.use(nudgesRouter);
apiRouter.use(gesturesRouter);
apiRouter.use(surprisesRouter);
apiRouter.use(privacyRouter);
apiRouter.use(settingsRouter);
