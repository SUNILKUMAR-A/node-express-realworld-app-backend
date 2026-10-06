import serverlessExpress from '@codegenie/serverless-express';
import app from './app';

export const handler = serverlessExpress({ app });

if (!process.env.AWS_LAMBDA_FUNCTION_NAME) {
  const PORT = process.env.PORT || 3000;

  app.listen(PORT, () => {
    console.info(`server up on port ${PORT}`);
  });
}
